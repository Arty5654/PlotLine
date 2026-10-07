package com.plotline.backend.accounts;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.FriendPost;
import com.plotline.backend.dto.S3UserRecord;
import com.plotline.backend.membership.Membership;
import com.plotline.backend.membership.MembershipService;
import com.plotline.backend.service.FriendsFeedService;

import jakarta.annotation.PostConstruct;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.S3Object;

import static com.plotline.backend.util.UsernameUtils.normalize;

/**
 * One-time copy of the old shared S3 files into Postgres, run on startup before the server takes
 * requests. Each part runs once (recorded in data_imports). The S3 files are left in place as a
 * backup and aren't read again.
 *
 * - accounts: every users/{name}/account.json (so accounts missing from all-users.json, lost to
 *   overlapping updates, come back), numbered in all-users.json order (sign-up order), then by
 *   creation time. Emails come from each account; if two share one, email-index.json decides.
 * - feed: friends-feed/posts.json
 * - memberships: users/{name}/subscription.json and app-store/subscriptions/{id}.json
 */
@Component
public class S3DataImport {
    private static final Logger log = LoggerFactory.getLogger(S3DataImport.class);


    private static final String BUCKET = "plotline-database-bucket";

    private final S3Client s3;
    private final JdbcTemplate jdbc;
    private final TransactionTemplate transaction;
    private final FriendsFeedService feed;
    private final MembershipService memberships;
    private final ObjectMapper mapper = new ObjectMapper()
            .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);

    public S3DataImport(S3Client s3, JdbcTemplate jdbc, TransactionTemplate transaction,
                        FriendsFeedService feed, MembershipService memberships) {
        this.s3 = s3;
        this.jdbc = jdbc;
        this.transaction = transaction;
        this.feed = feed;
        this.memberships = memberships;
    }

    @FunctionalInterface
    private interface Step {
        void run() throws Exception;
    }

    @PostConstruct
    public void importAll() {
        once("accounts", this::importAccounts);
        once("feed", this::importFeed);
        once("memberships", this::importMemberships);
    }

    // all or nothing, and only once even if two servers start together
    private void once(String name, Step step) {
        transaction.executeWithoutResult(status -> {
            jdbc.execute("lock table data_imports in exclusive mode");
            Integer done = jdbc.queryForObject("select count(*) from data_imports where name = ?", Integer.class, name);
            if (done != null && done > 0) return;
            try {
                step.run();
            } catch (Exception e) {
                throw new IllegalStateException("Couldn't copy " + name + " from S3 to the database", e);
            }
            jdbc.update("insert into data_imports (name) values (?)", name);
            log.info("Copied {} from S3 to the database", name);
        });
    }

    // ── Accounts ───────────────────────────────────────────────────────────────

    private record Account(String username, S3UserRecord record) { }

    private void importAccounts() throws Exception {
        List<String> signupOrder = new ArrayList<>();
        for (String name : readOr("all-users.json", new TypeReference<List<String>>() { }, List.of())) {
            signupOrder.add(normalize(name));
        }
        Map<String, String> emailOwners = new HashMap<>();
        readOr("email-index.json", new TypeReference<Map<String, String>>() { }, Map.<String, String>of())
                .forEach((email, owner) -> emailOwners.put(email.trim().toLowerCase(), normalize(owner)));

        Map<String, Account> accounts = new HashMap<>();
        for (String key : keys("users/")) {
            String[] parts = key.split("/");
            if (parts.length != 3 || !parts[2].equals("account.json")) continue;
            String username = normalize(parts[1]);
            S3UserRecord record = read(key, new TypeReference<S3UserRecord>() { });
            if (record != null) accounts.putIfAbsent(username, new Account(username, record));
        }

        List<Account> ordered = new ArrayList<>(accounts.values());
        ordered.sort(Comparator
                .comparingInt((Account a) -> {
                    int position = signupOrder.indexOf(a.username());
                    return position >= 0 ? position : Integer.MAX_VALUE;
                })
                .thenComparingLong(a -> a.record().getCreatedAt() != null ? a.record().getCreatedAt() : 0L)
                .thenComparing(Account::username));

        Set<String> usedEmails = new HashSet<>();
        for (Account account : ordered) {
            S3UserRecord record = account.record();
            String email = record.getEmail() != null && !record.getEmail().isBlank() ? record.getEmail().trim().toLowerCase() : null;
            String indexedOwner = email != null ? emailOwners.get(email) : null;
            if (email != null && indexedOwner != null && !indexedOwner.equals(account.username()) && accounts.containsKey(indexedOwner)) {
                log.warn("Email of {} belongs to {}; not copied", account.username(), indexedOwner);
                email = null;
            }
            if (email != null && !usedEmails.add(email)) {
                log.warn("Email of {} is already used by another account; not copied", account.username());
                email = null;
            }
            String display = record.getDisplayUsername() != null && !record.getDisplayUsername().isBlank()
                    ? record.getDisplayUsername() : account.username();
            long createdAt = record.getCreatedAt() != null && record.getCreatedAt() > 0 ? record.getCreatedAt() : System.currentTimeMillis();
            jdbc.update("""
                    insert into accounts (username, display_username, email, created_at)
                    values (?, ?, ?, to_timestamp(? / 1000.0))
                    on conflict do nothing
                    """, account.username(), display, email, createdAt);
        }
    }

    // ── Feed ───────────────────────────────────────────────────────────────────

    private void importFeed() throws Exception {
        List<FriendPost> posts = readOr("friends-feed/posts.json", new TypeReference<List<FriendPost>>() { }, List.of());
        Set<Object> seen = new LinkedHashSet<>();
        for (FriendPost post : posts) {
            if (post.getId() != null && !seen.add(post.getId())) continue; // the old file could hold a post twice
            feed.insert(post);
        }
    }

    // ── Memberships ────────────────────────────────────────────────────────────

    private void importMemberships() throws Exception {
        for (String key : keys("users/")) {
            String[] parts = key.split("/");
            if (parts.length != 3 || !parts[2].equals("subscription.json")) continue;
            Membership membership = read(key, new TypeReference<Membership>() { });
            if (membership != null && membership.getPlan() != null) memberships.write(parts[1], membership);
        }
        for (String key : keys("app-store/subscriptions/")) {
            String originalTransactionId = key.substring(key.lastIndexOf('/') + 1).replace(".json", "");
            Map<String, String> link = read(key, new TypeReference<Map<String, String>>() { });
            if (link != null && link.get("username") != null) memberships.link(originalTransactionId, link.get("username"));
        }
    }

    // ── S3 ─────────────────────────────────────────────────────────────────────

    private List<String> keys(String prefix) {
        List<String> keys = new ArrayList<>();
        String token = null;
        do {
            ListObjectsV2Response page = s3.listObjectsV2(ListObjectsV2Request.builder()
                    .bucket(BUCKET).prefix(prefix).continuationToken(token).build());
            for (S3Object object : page.contents()) keys.add(object.key());
            token = Boolean.TRUE.equals(page.isTruncated()) ? page.nextContinuationToken() : null;
        } while (token != null);
        return keys;
    }

    private <T> T read(String key, TypeReference<T> type) throws Exception {
        try {
            return mapper.readValue(s3.getObjectAsBytes(b -> b.bucket(BUCKET).key(key)).asByteArray(), type);
        } catch (NoSuchKeyException e) {
            return null;
        }
    }

    private <T> T readOr(String key, TypeReference<T> type, T fallback) throws Exception {
        T value = read(key, type);
        return value != null ? value : fallback;
    }
}
