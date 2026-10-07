package com.plotline.backend.features;

import com.apple.itunes.storekit.model.AutoRenewStatus;
import com.apple.itunes.storekit.model.Data;
import com.apple.itunes.storekit.model.Environment;
import com.apple.itunes.storekit.model.JWSRenewalInfoDecodedPayload;
import com.apple.itunes.storekit.model.JWSTransactionDecodedPayload;
import com.apple.itunes.storekit.model.NotificationTypeV2;
import com.apple.itunes.storekit.model.OfferDiscountType;
import com.apple.itunes.storekit.model.OfferType;
import com.apple.itunes.storekit.model.ResponseBodyV2DecodedPayload;
import com.apple.itunes.storekit.verification.VerificationException;
import com.apple.itunes.storekit.verification.VerificationStatus;
import com.fasterxml.jackson.databind.JsonNode;
import com.plotline.backend.membership.AppStoreVerifier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/**
 * Membership with the paywall ON. Nobody here is one of the first 1,000 accounts
 * (lifetime-accounts=0) and the free week is turned off (free-days=0; it has its own tests in
 * MembershipServiceTest), so new accounts start locked. Apple's signature check is faked: each
 * "signed" string the app sends maps to a transaction the test builds.
 */
@SpringBootTest(properties = {"plotline.ratelimit.enabled=false", "plotline.membership.required=true",
        "plotline.membership.lifetime-accounts=0", "plotline.membership.free-days=0"})
class MembershipFeatureTest extends FeatureTestBase {

    @MockBean private AppStoreVerifier appStoreVerifier;

    private final Map<String, JWSTransactionDecodedPayload> signedTransactions = new HashMap<>();
    private final Map<String, JWSRenewalInfoDecodedPayload> signedRenewals = new HashMap<>();
    private final Map<String, ResponseBodyV2DecodedPayload> signedNotifications = new HashMap<>();

    private static final long DAY = Duration.ofDays(1).toMillis();

    @BeforeEach
    void fakeApple() throws Exception {
        VerificationException forged = new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
        when(appStoreVerifier.transaction(anyString())).thenAnswer(i -> {
            JWSTransactionDecodedPayload t = signedTransactions.get(i.<String>getArgument(0));
            if (t == null) throw forged;
            return t;
        });
        when(appStoreVerifier.renewalInfo(anyString())).thenAnswer(i -> {
            JWSRenewalInfoDecodedPayload r = signedRenewals.get(i.<String>getArgument(0));
            if (r == null) throw forged;
            return r;
        });
        when(appStoreVerifier.notification(anyString())).thenAnswer(i -> {
            ResponseBodyV2DecodedPayload n = signedNotifications.get(i.<String>getArgument(0));
            if (n == null) throw forged;
            return n;
        });
    }

    // ── Apple data ─────────────────────────────────────────────────────────────

    private String signed(JWSTransactionDecodedPayload transaction) {
        String jws = "jws-" + UUID.randomUUID();
        signedTransactions.put(jws, transaction);
        return jws;
    }

    private static JWSTransactionDecodedPayload transaction(String originalId, long expiresAt, boolean freeTrial) {
        JWSTransactionDecodedPayload t = new JWSTransactionDecodedPayload()
                .originalTransactionId(originalId)
                .transactionId(UUID.randomUUID().toString())
                .bundleId(AppStoreVerifier.BUNDLE_ID)
                .productId("plus_monthly")
                .expiresDate(expiresAt)
                .environment(Environment.SANDBOX);
        if (freeTrial) {
            t.offerType(OfferType.INTRODUCTORY_OFFER).offerDiscountType(OfferDiscountType.FREE_TRIAL);
        }
        return t;
    }

    private static String newSubscriptionId() {
        return String.valueOf(Math.abs(UUID.randomUUID().getMostSignificantBits()));
    }

    private void sendNotification(NotificationTypeV2 type, JWSTransactionDecodedPayload transaction,
                                  JWSRenewalInfoDecodedPayload renewal) throws Exception {
        Data data = new Data().signedTransactionInfo(signed(transaction));
        if (renewal != null) {
            String jws = "renewal-" + UUID.randomUUID();
            signedRenewals.put(jws, renewal);
            data.signedRenewalInfo(jws);
        }
        String payload = "notification-" + UUID.randomUUID();
        signedNotifications.put(payload, new ResponseBodyV2DecodedPayload().notificationType(type).data(data));

        // Apple's servers send no login token and no API key
        ok(post("/api/payments/apple/notifications").contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(Map.of("signedPayload", payload))));
    }

    // ── App calls ──────────────────────────────────────────────────────────────

    private JsonNode status(User user) throws Exception {
        return ok(getAs(user, "/api/payments/status/{u}", user.name()));
    }

    private JsonNode sync(User user, String signedTransaction, int expectedStatus) throws Exception {
        return call(postJson(user, "/api/payments/apple/sync", Map.of("signedTransaction", signedTransaction)), expectedStatus);
    }

    /** any ordinary endpoint: 200 when unlocked, 402 when locked */
    private int appStatus(User user) throws Exception {
        return mockMvc.perform(getAs(user, "/friends/get-friends").param("username", user.name()))
                .andReturn().getResponse().getStatus();
    }

    // ── Tests ──────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("A new account is locked out of the app but can reach the paywall")
    void newAccountLocked() throws Exception {
        User me = newUser();

        JsonNode locked = call(getAs(me, "/friends/get-friends").param("username", me.name()), 402);
        assertThat(locked.get("error").asText()).isEqualTo("Membership Required");

        JsonNode status = status(me);
        assertThat(status.get("plan").asText()).isEqualTo("free-week");
        assertThat(status.get("active").asBoolean()).isFalse();
        ok(as(me, post("/auth/refresh"))); // staying signed in still works
    }

    @Test
    @DisplayName("Starting the App Store free trial unlocks the app until the trial ends")
    void freeTrialUnlocks() throws Exception {
        User me = newUser();
        long trialEnd = System.currentTimeMillis() + 30 * DAY;

        JsonNode status = sync(me, signed(transaction(newSubscriptionId(), trialEnd, true)), 200);

        assertThat(status.get("plan").asText()).isEqualTo("trial");
        assertThat(status.get("active").asBoolean()).isTrue();
        assertThat(status.get("expiresAt").asText()).isEqualTo(java.time.Instant.ofEpochMilli(trialEnd).toString());
        assertThat(appStatus(me)).isEqualTo(200);
    }

    @Test
    @DisplayName("An expired subscription stays locked")
    void expiredStaysLocked() throws Exception {
        User me = newUser();
        sync(me, signed(transaction(newSubscriptionId(), System.currentTimeMillis() - DAY, false)), 200);

        assertThat(status(me).get("active").asBoolean()).isFalse();
        assertThat(appStatus(me)).isEqualTo(402);
    }

    @Test
    @DisplayName("One App Store subscription unlocks only one PlotLine account")
    void oneAccountPerSubscription() throws Exception {
        User first = newUser();
        User second = newUser();
        JWSTransactionDecodedPayload subscription = transaction(newSubscriptionId(), System.currentTimeMillis() + 30 * DAY, true);
        sync(first, signed(subscription), 200);

        JsonNode refused = sync(second, signed(subscription), 409);

        assertThat(refused.get("error").asText()).contains("already used by another PlotLine account");
        assertThat(appStatus(second)).isEqualTo(402);
        assertThat(appStatus(first)).isEqualTo(200);
        sync(first, signed(subscription), 200); // restoring on the same account is fine
    }

    @Test
    @DisplayName("Purchases that don't verify, or aren't the membership, are refused")
    void refusesBadPurchases() throws Exception {
        User me = newUser();
        sync(me, "forged", 400);

        JWSTransactionDecodedPayload otherProduct = transaction(newSubscriptionId(), System.currentTimeMillis() + DAY, false)
                .productId("something_else");
        sync(me, signed(otherProduct), 400);

        assertThat(appStatus(me)).isEqualTo(402);
    }

    @Test
    @DisplayName("Apple's renewal notice extends access and switches the trial to monthly")
    void renewalNotification() throws Exception {
        User me = newUser();
        String id = newSubscriptionId();
        long now = System.currentTimeMillis();
        sync(me, signed(transaction(id, now + DAY, true)), 200);

        sendNotification(NotificationTypeV2.DID_RENEW, transaction(id, now + 31 * DAY, false),
                new JWSRenewalInfoDecodedPayload().originalTransactionId(id).autoRenewStatus(AutoRenewStatus.ON));

        JsonNode status = status(me);
        assertThat(status.get("plan").asText()).isEqualTo("monthly");
        assertThat(status.get("expiresAt").asText()).isEqualTo(java.time.Instant.ofEpochMilli(now + 31 * DAY).toString());
        assertThat(status.get("autoRenews").asBoolean()).isTrue();

        // an older notice arriving late doesn't undo the renewal
        sendNotification(NotificationTypeV2.DID_CHANGE_RENEWAL_STATUS, transaction(id, now + DAY, true), null);
        assertThat(status(me).get("plan").asText()).isEqualTo("monthly");
    }

    @Test
    @DisplayName("Turning off auto-renew keeps access until the period ends")
    void cancelKeepsAccessUntilExpiry() throws Exception {
        User me = newUser();
        String id = newSubscriptionId();
        JWSTransactionDecodedPayload current = transaction(id, System.currentTimeMillis() + 10 * DAY, false);
        sync(me, signed(current), 200);

        sendNotification(NotificationTypeV2.DID_CHANGE_RENEWAL_STATUS, current,
                new JWSRenewalInfoDecodedPayload().originalTransactionId(id).autoRenewStatus(AutoRenewStatus.OFF));

        JsonNode status = status(me);
        assertThat(status.get("autoRenews").asBoolean()).isFalse();
        assertThat(status.get("active").asBoolean()).isTrue();
    }

    @Test
    @DisplayName("A refund locks the account right away")
    void refundLocks() throws Exception {
        User me = newUser();
        String id = newSubscriptionId();
        long expires = System.currentTimeMillis() + 20 * DAY;
        sync(me, signed(transaction(id, expires, false)), 200);

        sendNotification(NotificationTypeV2.REFUND,
                transaction(id, expires, false).revocationDate(System.currentTimeMillis()), null);

        assertThat(status(me).get("revoked").asBoolean()).isTrue();
        assertThat(appStatus(me)).isEqualTo(402);
    }

    @Test
    @DisplayName("Billing problems: access continues through Apple's grace period")
    void billingGracePeriod() throws Exception {
        User me = newUser();
        String id = newSubscriptionId();
        long now = System.currentTimeMillis();
        JWSTransactionDecodedPayload lapsed = transaction(id, now - DAY, false);
        sync(me, signed(lapsed), 200);
        assertThat(appStatus(me)).isEqualTo(402);

        sendNotification(NotificationTypeV2.DID_FAIL_TO_RENEW, lapsed, new JWSRenewalInfoDecodedPayload()
                .originalTransactionId(id).isInBillingRetryPeriod(true).gracePeriodExpiresDate(now + 6 * DAY));

        assertThat(appStatus(me)).isEqualTo(200);
    }

    @Test
    @DisplayName("Notices about subscriptions no account uses yet are accepted and ignored; forged ones are refused")
    void unknownAndForgedNotifications() throws Exception {
        User me = newUser();
        sendNotification(NotificationTypeV2.SUBSCRIBED, transaction(newSubscriptionId(), System.currentTimeMillis() + DAY, true), null);
        assertThat(appStatus(me)).isEqualTo(402);

        call(post("/api/payments/apple/notifications").contentType(MediaType.APPLICATION_JSON)
                .content("{\"signedPayload\": \"forged\"}"), 400);
    }

    @Test
    @DisplayName("Deleting an account frees its subscription for another account")
    void deletionFreesSubscription() throws Exception {
        User first = newUser();
        User second = newUser();
        JWSTransactionDecodedPayload subscription = transaction(newSubscriptionId(), System.currentTimeMillis() + 30 * DAY, false);
        sync(first, signed(subscription), 200);

        ok(postJson(first, "/auth/delete-account", Map.of())); // allowed even though it's the paywall's only way out
        sync(second, signed(subscription), 200);

        assertThat(appStatus(second)).isEqualTo(200);
    }
}
