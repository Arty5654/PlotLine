package com.plotline.backend.membership;

import java.time.Duration;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.BeanPropertyRowMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import com.apple.itunes.storekit.model.AutoRenewStatus;
import com.apple.itunes.storekit.model.JWSRenewalInfoDecodedPayload;
import com.apple.itunes.storekit.model.JWSTransactionDecodedPayload;
import com.apple.itunes.storekit.model.OfferDiscountType;
import com.apple.itunes.storekit.model.OfferType;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.plotline.backend.service.AuthService;

import static com.plotline.backend.util.UsernameUtils.normalize;

/**
 * Who can use PlotLine: the first 1,000 accounts free forever; everyone else gets a free week
 * from sign-up (no payment needed), then needs an active App Store subscription (which starts
 * with Apple's free month). Each App Store subscription unlocks one PlotLine account.
 * Stored in Postgres: memberships, and app_store_subscriptions for which account uses each
 * subscription.
 */
@Service
public class MembershipService {

    public static final String PRODUCT_ID = "plus_monthly";

    /** sync result: the account's membership, or why the purchase wasn't applied */
    public record SyncResult(Membership membership, String error) {
        static SyncResult failed(String error) { return new SyncResult(null, error); }
    }

    public static final String ALREADY_LINKED =
            "This App Store subscription is already used by another PlotLine account.";

    private final JdbcTemplate jdbc;
    private final AuthService authService;
    private final int lifetimeAccounts;
    private final Duration freeWeek;
    private final ObjectMapper mapper = new ObjectMapper();

    // checked on every request, so kept in memory briefly (always updated on our own writes)
    private final Cache<String, Membership> cache = Caffeine.newBuilder()
            .expireAfterWrite(Duration.ofMinutes(1))
            .maximumSize(50_000)
            .build();

    public MembershipService(JdbcTemplate jdbc, AuthService authService,
                             @Value("${plotline.membership.lifetime-accounts:1000}") int lifetimeAccounts,
                             @Value("${plotline.membership.free-days:7}") int freeDays) {
        this.jdbc = jdbc;
        this.authService = authService;
        this.lifetimeAccounts = lifetimeAccounts;
        this.freeWeek = Duration.ofDays(freeDays);
    }

    public boolean hasAccess(String username) {
        return membership(username).isActive(System.currentTimeMillis());
    }

    /**
     * The stored membership. The first time (or for old files), decides between lifetime (one of
     * the first 1,000 accounts) and the free week, which counts from when the account was created.
     */
    public Membership membership(String username) {
        String user = normalize(username);
        return cache.get(user, u -> {
            Membership stored = read(u);
            if (stored != null && !stored.isLegacy()) return stored;
            Membership fresh;
            if (isEarlyAccount(u)) {
                fresh = Membership.of(Membership.LIFETIME);
            } else {
                fresh = Membership.of(Membership.FREE_WEEK);
                fresh.setExpiresAt(accountCreatedAt(u) + freeWeek.toMillis());
            }
            write(u, fresh);
            return fresh;
        });
    }

    // accounts from before creation times were recorded start their week now
    private long accountCreatedAt(String username) {
        var record = authService.getUserRecord(username);
        Long createdAt = record != null ? record.getCreatedAt() : null;
        return createdAt != null && createdAt > 0 ? createdAt : System.currentTimeMillis();
    }

    // counted among accounts that still exist, in sign-up order
    private boolean isEarlyAccount(String username) {
        Long rank = authService.signupRank(username);
        return rank != null && rank <= lifetimeAccounts;
    }

    /** a purchase or restore from the app, already verified by AppStoreVerifier */
    public synchronized SyncResult applyPurchase(String username, JWSTransactionDecodedPayload transaction) {
        String user = normalize(username);
        if (!PRODUCT_ID.equals(transaction.getProductId()) || transaction.getOriginalTransactionId() == null) {
            return SyncResult.failed("That purchase isn't a PlotLine membership.");
        }
        // the first account to send this subscription keeps it (one insert, so two at once can't both win)
        link(transaction.getOriginalTransactionId(), user);
        if (!user.equals(linkedAccount(transaction.getOriginalTransactionId()))) {
            return SyncResult.failed(ALREADY_LINKED);
        }
        return new SyncResult(apply(user, transaction, null), null);
    }

    /** an App Store Server Notification about a subscription; ignored if no account uses it yet */
    public synchronized void applyNotification(JWSTransactionDecodedPayload transaction, JWSRenewalInfoDecodedPayload renewal) {
        if (!PRODUCT_ID.equals(transaction.getProductId()) || transaction.getOriginalTransactionId() == null) return;
        String owner = linkedAccount(transaction.getOriginalTransactionId());
        if (owner == null) return; // the app links it right after the purchase
        apply(owner, transaction, renewal);
    }

    private Membership apply(String user, JWSTransactionDecodedPayload transaction, JWSRenewalInfoDecodedPayload renewal) {
        // a copy, so the cached one only changes once the new one is saved
        Membership membership = mapper.convertValue(membership(user), Membership.class);
        if (Membership.LIFETIME.equals(membership.getPlan())) return membership;
        Long expires = transaction.getExpiresDate();
        if (expires == null) return membership;

        // updates can arrive out of order: ignore anything older than what we already know
        boolean sameSubscription = transaction.getOriginalTransactionId().equals(membership.getOriginalTransactionId());
        if (sameSubscription && membership.getTransactionExpiresAt() != null && expires < membership.getTransactionExpiresAt()) {
            return membership;
        }

        long accessUntil = expires;
        if (renewal != null && Boolean.TRUE.equals(renewal.getIsInBillingRetryPeriod())
                && renewal.getGracePeriodExpiresDate() != null) {
            accessUntil = Math.max(accessUntil, renewal.getGracePeriodExpiresDate()); // Apple's billing grace period
        }
        boolean freeTrial = transaction.getOfferType() == OfferType.INTRODUCTORY_OFFER
                && transaction.getOfferDiscountType() == OfferDiscountType.FREE_TRIAL;

        membership.setPlan(freeTrial ? Membership.TRIAL : Membership.MONTHLY);
        membership.setExpiresAt(accessUntil);
        membership.setTransactionExpiresAt(expires);
        membership.setRevoked(transaction.getRevocationDate() != null);
        membership.setOriginalTransactionId(transaction.getOriginalTransactionId());
        membership.setEnvironment(transaction.getEnvironment() != null ? transaction.getEnvironment().getValue() : null);
        if (renewal != null && renewal.getAutoRenewStatus() != null) {
            membership.setAutoRenews(renewal.getAutoRenewStatus() == AutoRenewStatus.ON);
        } else if (!sameSubscription) {
            membership.setAutoRenews(null);
        }
        write(user, membership);
        cache.put(user, membership);
        return membership;
    }

    /** account deletion: free the App Store subscription so another account can use it */
    public synchronized void forget(String username) {
        String user = normalize(username);
        jdbc.update("delete from app_store_subscriptions where username = ?", user);
        jdbc.update("delete from memberships where username = ?", user);
        cache.invalidate(user);
    }

    private String linkedAccount(String originalTransactionId) {
        List<String> owner = jdbc.queryForList(
                "select username from app_store_subscriptions where original_transaction_id = ?", String.class, originalTransactionId);
        return owner.isEmpty() ? null : owner.get(0);
    }

    // ── Postgres ───────────────────────────────────────────────────────────────

    private Membership read(String user) {
        List<Membership> rows = jdbc.query("select * from memberships where username = ?",
                new BeanPropertyRowMapper<>(Membership.class), user);
        return rows.isEmpty() ? null : rows.get(0);
    }

    /** also used to copy the old S3 files into the database (S3DataImport) */
    public void write(String username, Membership m) {
        jdbc.update("""
                insert into memberships (username, plan, expires_at, transaction_expires_at, auto_renews, revoked,
                                         original_transaction_id, environment)
                values (?, ?, ?, ?, ?, ?, ?, ?)
                on conflict (username) do update set plan = excluded.plan, expires_at = excluded.expires_at,
                    transaction_expires_at = excluded.transaction_expires_at, auto_renews = excluded.auto_renews,
                    revoked = excluded.revoked, original_transaction_id = excluded.original_transaction_id,
                    environment = excluded.environment
                """, normalize(username), m.getPlan(), m.getExpiresAt(), m.getTransactionExpiresAt(), m.getAutoRenews(),
                m.isRevoked(), m.getOriginalTransactionId(), m.getEnvironment());
    }

    /** an App Store subscription's account, unless it already has one (also used by S3DataImport) */
    public void link(String originalTransactionId, String username) {
        jdbc.update("insert into app_store_subscriptions (original_transaction_id, username) values (?, ?) on conflict do nothing",
                originalTransactionId, normalize(username));
    }
}
