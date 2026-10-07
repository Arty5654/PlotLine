package com.plotline.backend.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.accounts.AccountDirectory;
import com.plotline.backend.categorize.UserCategoryStore;
import com.plotline.backend.dto.AuthResponse;
import com.plotline.backend.dto.S3UserRecord;
import com.plotline.backend.membership.MembershipService;
import com.plotline.backend.plaid.PlaidCursorStore;
import com.plotline.backend.plaid.TokenStore;
import com.plotline.backend.service.AppleTokenRevoker.AppleTokens;
import com.plaid.client.model.ItemRemoveRequest;
import com.plaid.client.request.PlaidApi;

import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.S3Object;

import static com.plotline.backend.util.UsernameUtils.normalize;

/**
 * Permanently deletes an account and everything tied to it (App Store rule 5.1.1(v)).
 *
 * Order matters: links to other people (friends, shared grocery lists, feed) and outside
 * services (Plaid, Apple) are cleaned up first, and the account record + indexes are deleted
 * last. If anything fails part-way, the account still exists and the user can simply retry.
 */
@Service
public class AccountDeletionService {
    private static final Logger log = LoggerFactory.getLogger(AccountDeletionService.class);


    public static final String APPLE_AUTHORIZATION_REQUIRED = "Apple Authorization Required";

    private static final String BUCKET = "plotline-database-bucket";

    private final S3Client s3Client;
    private final AuthService authService;
    private final AppleSignInService appleSignInService;
    private final AppleTokenRevoker appleTokenRevoker;
    private final FriendsService friendsService;
    private final FriendsFeedService friendsFeedService;
    private final GroceryListService groceryListService;
    private final TokenStore tokenStore;
    private final PlaidCursorStore plaidCursorStore;
    private final UserCategoryStore userCategoryStore;
    private final PlaidApi plaidApi;
    private final MembershipService membershipService;
    private final AccountDirectory accountDirectory;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public AccountDeletionService(S3Client s3Client, AuthService authService, AppleSignInService appleSignInService,
                                  AppleTokenRevoker appleTokenRevoker, FriendsService friendsService,
                                  FriendsFeedService friendsFeedService, GroceryListService groceryListService,
                                  TokenStore tokenStore, PlaidCursorStore plaidCursorStore,
                                  UserCategoryStore userCategoryStore, PlaidApi plaidApi,
                                  MembershipService membershipService, AccountDirectory accountDirectory) {
        this.s3Client = s3Client;
        this.authService = authService;
        this.appleSignInService = appleSignInService;
        this.appleTokenRevoker = appleTokenRevoker;
        this.friendsService = friendsService;
        this.friendsFeedService = friendsFeedService;
        this.groceryListService = groceryListService;
        this.tokenStore = tokenStore;
        this.plaidCursorStore = plaidCursorStore;
        this.userCategoryStore = userCategoryStore;
        this.plaidApi = plaidApi;
        this.membershipService = membershipService;
        this.accountDirectory = accountDirectory;
    }

    public AuthResponse deleteAccount(String username, String appleAuthorizationCode) {
        String user = normalize(username);
        S3UserRecord record = authService.getUserRecord(user);
        if (record == null) {
            return fail("Account not found");
        }

        // 1. Apple: revoke our access to their Apple ID (needs a fresh code from the app)
        if (record.getAppleSub() != null) {
            if (appleTokenRevoker.isConfigured()) {
                if (appleAuthorizationCode == null || appleAuthorizationCode.isBlank()) {
                    return fail(APPLE_AUTHORIZATION_REQUIRED);
                }
                try {
                    AppleTokens tokens = appleTokenRevoker.exchangeCode(appleAuthorizationCode);
                    if (!record.getAppleSub().equals(tokens.subject())) {
                        return fail("Please use the Apple ID connected to this account.");
                    }
                    appleTokenRevoker.revoke(tokens.refreshToken());
                } catch (Exception e) {
                    log.error("deleteAccount failed", e);
                    return fail("Couldn't disconnect your Apple ID. Please try again.");
                }
            } else {
                log.warn("WARNING: Apple sign-in key not configured, skipping Apple token revocation for {}", user);
            }
        }

        // Plaid data was keyed by whatever username the app sent, which may be the display casing
        Set<String> usernameVariants = new LinkedHashSet<>(List.of(user));
        if (record.getDisplayUsername() != null && !record.getDisplayUsername().isBlank()) {
            usernameVariants.add(record.getDisplayUsername());
        }

        // 2. Plaid: disconnect linked banks, then forget tokens and sync state
        for (String variant : usernameVariants) {
            for (String accessToken : tokenStore.listAccessTokens(variant).values()) {
                try {
                    removePlaidItem(accessToken);
                } catch (Exception e) {
                    log.error("Plaid item removal failed during account deletion: {}", e.getMessage());
                }
            }
            tokenStore.deleteUser(variant);
            plaidCursorStore.clearSyncState(variant);
            userCategoryStore.deleteUser(variant);
        }

        // 3. Friends: unfriend everyone (also revokes calendar access and event invites both ways)
        try {
            for (String friend : new ArrayList<>(friendsService.getFriendList(user).getFriends())) {
                try {
                    friendsService.removeFriend(user, friend);
                } catch (Exception e) {
                    log.error("Failed to remove friend {}: {}", friend, e.getMessage());
                }
            }
        } catch (Exception e) {
            log.error("Failed to load friends during account deletion: {}", e.getMessage());
        }

        // 4. Grocery: delete owned lists (and members' pointers), leave lists shared with us,
        //    and remove the other side of any pending invites
        cleanUpGrocery(user);

        // 5. Friends feed: posts, likes and comments
        try {
            friendsFeedService.removeUser(user);
        } catch (Exception e) {
            log.error("Failed to clean friends feed: {}", e.getMessage());
        }

        // 6. Membership: free their App Store subscription for another account (the subscription
        //    itself is managed by Apple, and deleting the account doesn't cancel it)
        try {
            membershipService.forget(user);
        } catch (Exception e) {
            log.error("Failed to release App Store subscription: {}", e.getMessage());
        }

        // 7. Everything stored under the user (account.json is kept for last)
        try {
            deletePrefix("chat-messages/" + user + "/");
            deletePrefix("users/" + user + "/", "users/" + user + "/account.json");
        } catch (Exception e) {
            log.error("deleteAccount failed", e);
            return fail("Couldn't delete your data. Please try again.");
        }

        // 8. Username and email (frees them for new accounts), Apple link, and finally the account itself
        try {
            accountDirectory.delete(user);
            if (record.getAppleSub() != null) {
                appleSignInService.deleteLink(record.getAppleSub());
            }
            s3Client.deleteObject(DeleteObjectRequest.builder().bucket(BUCKET).key("users/" + user + "/account.json").build());
            authService.evictAccountCache(user);
        } catch (Exception e) {
            log.error("deleteAccount failed", e);
            return fail("Couldn't delete your account. Please try again.");
        }

        log.info("Account DELETED: {}", user);
        return new AuthResponse(true, null, null);
    }

    // overridden in tests
    void removePlaidItem(String accessToken) throws Exception {
        plaidApi.itemRemove(new ItemRemoveRequest().accessToken(accessToken)).execute();
    }

    private void cleanUpGrocery(String user) {
        String base = "users/" + user + "/grocery/";
        try {
            for (String key : listKeys(base + "lists/")) {
                groceryListService.deleteGroceryList(user, fileId(key));
            }
            for (String key : listKeys(base + "shared/")) {
                groceryListService.deleteGroceryList(user, fileId(key));
            }
            for (String key : listKeys(base + "invites/sent/")) {
                String to = readField(key, "toUsername");
                if (to != null) deleteKey("users/" + normalize(to) + "/grocery/invites/received/" + fileNameOf(key));
            }
            for (String key : listKeys(base + "invites/received/")) {
                String from = readField(key, "fromUsername");
                if (from != null) deleteKey("users/" + normalize(from) + "/grocery/invites/sent/" + fileNameOf(key));
            }
        } catch (Exception e) {
            log.error("Failed to clean up grocery lists: {}", e.getMessage());
        }
    }

    // ── S3 helpers ─────────────────────────────────────────────────────────────

    private void deletePrefix(String prefix, String... keep) {
        Set<String> kept = Set.of(keep);
        for (String key : listKeys(prefix)) {
            if (!kept.contains(key)) deleteKey(key);
        }
    }

    private List<String> listKeys(String prefix) {
        List<String> keys = new ArrayList<>();
        String continuationToken = null;
        do {
            ListObjectsV2Response page = s3Client.listObjectsV2(ListObjectsV2Request.builder()
                    .bucket(BUCKET).prefix(prefix).continuationToken(continuationToken).build());
            for (S3Object object : page.contents()) keys.add(object.key());
            continuationToken = Boolean.TRUE.equals(page.isTruncated()) ? page.nextContinuationToken() : null;
        } while (continuationToken != null);
        return keys;
    }

    private void deleteKey(String key) {
        s3Client.deleteObject(DeleteObjectRequest.builder().bucket(BUCKET).key(key).build());
    }

    private String readField(String key, String field) {
        try {
            JsonNode node = objectMapper.readTree(s3Client.getObjectAsBytes(b -> b.bucket(BUCKET).key(key)).asByteArray());
            return node.hasNonNull(field) ? node.get(field).asText() : null;
        } catch (Exception e) {
            return null;
        }
    }

    private static String fileNameOf(String key) {
        return key.substring(key.lastIndexOf('/') + 1);
    }

    private static String fileId(String key) {
        String name = fileNameOf(key);
        return name.endsWith(".json") ? name.substring(0, name.length() - 5) : name;
    }

    private static AuthResponse fail(String message) {
        return new AuthResponse(false, null, message);
    }
}
