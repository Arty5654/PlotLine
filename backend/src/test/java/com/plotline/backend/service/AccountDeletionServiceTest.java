package com.plotline.backend.service;

import com.plotline.backend.accounts.AccountDirectory;
import com.plotline.backend.testsupport.TestDatabase;
import org.springframework.jdbc.core.JdbcTemplate;
import com.plotline.backend.categorize.InMemoryUserCategoryStore;
import com.plotline.backend.dto.AuthResponse;
import com.plotline.backend.dto.FriendPost;
import com.plotline.backend.dto.FriendRequest;
import com.plotline.backend.dto.GroceryList;
import com.plotline.backend.dto.GroceryListInvite;
import com.plotline.backend.dto.Trophy;
import com.plotline.backend.membership.MembershipService;
import com.plotline.backend.plaid.InMemoryPlaidCursorStore;
import com.plotline.backend.plaid.InMemoryTokenStore;
import com.plotline.backend.service.AppleTokenRevoker.AppleTokens;
import com.plotline.backend.testsupport.InMemoryS3Client;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Hermetic tests for account deletion. Real services run against the in-memory S3 double;
 * only Plaid's API and Apple's token endpoints are faked.
 */
class AccountDeletionServiceTest {

    private static final String BUCKET = "plotline-database-bucket";
    private static final String APPLE_SUB = "001234.abcdef.1234";

    private InMemoryS3Client s3;
    private AuthService authService;
    private FriendsService friendsService;
    private FriendsFeedService feedService;
    private GroceryListService groceryService;
    private InMemoryTokenStore tokenStore;
    private FakeAppleRevoker appleRevoker;
    private AccountDeletionService deletion;
    private JdbcTemplate jdbc;
    private final List<String> removedPlaidTokens = new ArrayList<>();

    private static class NoOpUserProfileService extends UserProfileService {
        NoOpUserProfileService(InMemoryS3Client s3) {
            super(s3, null);
        }
        @Override
        public List<Trophy> incrementTrophy(String username, String trophyId, int amount) {
            return Collections.emptyList();
        }
    }

    private static class FakeAppleRevoker extends AppleTokenRevoker {
        boolean configured = true;
        String subjectForCode = APPLE_SUB;
        final List<String> revoked = new ArrayList<>();

        FakeAppleRevoker() {
            super("TEAM", "KEY", "unused", "com.test.PlotLine");
        }
        @Override public boolean isConfigured() { return configured; }
        @Override public AppleTokens exchangeCode(String code) { return new AppleTokens(subjectForCode, "refresh-" + code); }
        @Override public void revoke(String refreshToken) { revoked.add(refreshToken); }
    }

    @BeforeEach
    void setUp() {
        s3 = new InMemoryS3Client();
        jdbc = new JdbcTemplate(TestDatabase.newDatabase());
        authService = new AuthService(s3, null, "test-jwt-secret", new AccountDirectory(jdbc));
        UserProfileService profiles = new NoOpUserProfileService(s3);
        CalendarAccessService calendarAccess = new CalendarAccessService(s3);
        friendsService = new FriendsService(s3, calendarAccess, new CalendarService(s3, profiles, calendarAccess));
        feedService = new FriendsFeedService(s3, jdbc);
        groceryService = new GroceryListService(s3, profiles);
        tokenStore = new InMemoryTokenStore();
        appleRevoker = new FakeAppleRevoker();
        AppleSignInService appleSignIn = new AppleSignInService(authService,
                new AppleIdTokenVerifier("com.test.PlotLine", kid -> null), s3);

        deletion = new AccountDeletionService(s3, authService, appleSignIn, appleRevoker, friendsService,
                feedService, groceryService, tokenStore, new InMemoryPlaidCursorStore(),
                new InMemoryUserCategoryStore(), null,
                new MembershipService(jdbc, authService, 1000, 7), new AccountDirectory(jdbc)) {
            @Override
            void removePlaidItem(String accessToken) {
                removedPlaidTokens.add(accessToken);
            }
        };
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private String createList(String user, String name) throws Exception {
        GroceryList list = new GroceryList();
        list.setName(name);
        list.setUsername(user);
        list.setItems(new ArrayList<>());
        return groceryService.createGroceryList(list, user);
    }

    private void befriend(String a, String b) throws Exception {
        friendsService.createOrUpdateFriendRequest(new FriendRequest(a, b, "PENDING"));
        friendsService.acceptFriendRequest(new FriendRequest(a, b, "ACCEPTED"));
    }

    private UUID post(String user, String text) {
        FriendPost post = new FriendPost();
        post.setId(UUID.randomUUID());
        post.setUsername(user);
        post.setComment(text);
        feedService.addPostToFeed(post);
        return post.getId();
    }

    private List<FriendPost> feed() {
        return feedService.getFriendsFeed("bob");
    }

    private List<String> keysStartingWith(String prefix) {
        List<String> keys = new ArrayList<>();
        s3.listObjectsV2(b -> b.bucket(BUCKET).prefix(prefix)).contents().forEach(o -> keys.add(o.key()));
        return keys;
    }

    // ── Tests ──────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("Deleting an account removes its data and cleans up everything other users see")
    void deletesEverything() throws Exception {
        authService.createUser("555", "alice@mail.com", "alice", "Alice", "Password1", false);
        authService.createUser("556", "bob@mail.com", "bob", "bob", "Password1", false);
        authService.createUser("557", "carol@mail.com", "carol", "carol", "Password1", false);
        befriend("alice", "bob");

        // alice's list shared with bob, bob's list shared with alice, and a pending invite to carol
        String aliceList = createList("alice", "Alice groceries");
        GroceryListInvite toBob = groceryService.shareGroceryList("alice", "bob", aliceList);
        groceryService.respondToGroceryShare("bob", toBob.getId(), true);
        String bobList = createList("bob", "Bob groceries");
        GroceryListInvite toAlice = groceryService.shareGroceryList("bob", "alice", bobList);
        groceryService.respondToGroceryShare("alice", toAlice.getId(), true);
        String secondList = createList("alice", "For carol");
        GroceryListInvite toCarol = groceryService.shareGroceryList("alice", "carol", secondList);

        // feed activity
        post("alice", "my goal");
        UUID bobPost = post("bob", "bob's goal");
        feedService.toggleLike("alice", bobPost);
        feedService.addComment("alice", bobPost, "nice!");
        feedService.addComment("bob", bobPost, "thanks");

        // other personal data
        tokenStore.saveAccessToken("Alice", "item-1", "access-1");
        s3.putRaw("chat-messages/alice/m1.json", "{}".getBytes());
        s3.putRaw("users/alice/nutrition/2026-09-25.json", "{}".getBytes());

        AuthResponse response = deletion.deleteAccount("alice", null);

        assertThat(response.isSuccess()).isTrue();

        // alice's own data
        assertThat(keysStartingWith("users/alice/")).isEmpty();
        assertThat(keysStartingWith("chat-messages/alice/")).isEmpty();
        assertThat(authService.userExists("alice")).isFalse();
        assertThat(jdbc.queryForList("select username from accounts", String.class)).containsExactlyInAnyOrder("bob", "carol");
        assertThat(authService.usernameForEmail("alice@mail.com")).isNull();

        // Plaid disconnected
        assertThat(removedPlaidTokens).containsExactly("access-1");
        assertThat(tokenStore.listAccessTokens("Alice")).isEmpty();
        assertThat(tokenStore.usernameForItem("item-1")).isNull();

        // friends
        assertThat(friendsService.getFriendList("bob").getFriends()).doesNotContain("alice");

        // grocery: bob loses access to alice's list, alice leaves bob's list, carol's invite is gone
        assertThat(s3.contains("users/bob/grocery/shared/" + aliceList.toUpperCase() + ".json")).isFalse();
        assertThat(groceryService.getGroceryList("bob", bobList).getMembers()).doesNotContain("alice");
        assertThat(s3.contains("users/carol/grocery/invites/received/" + toCarol.getId() + ".json")).isFalse();

        // feed
        List<FriendPost> feed = feed();
        assertThat(feed).extracting(FriendPost::getUsername).containsExactly("bob");
        assertThat(feed.get(0).getLikedBy()).doesNotContain("alice");
        assertThat(feed.get(0).getComments()).containsExactly("bob: thanks");
        assertThat(jdbc.queryForList("select author from feed_posts", String.class)).containsExactly("bob");

        // other users untouched
        assertThat(authService.userExists("bob")).isTrue();
        assertThat(groceryService.getGroceryList("bob", bobList)).isNotNull();
    }

    @Test
    @DisplayName("The username and email can be used again, with nothing carried over")
    void usernameCanBeReused() throws Exception {
        authService.createUser("555", "alice@mail.com", "alice", "alice", "Password1", false);
        authService.createUser("556", "bob@mail.com", "bob", "bob", "Password1", false);
        befriend("alice", "bob");

        deletion.deleteAccount("alice", null);

        assertThat(authService.createUser("999", "alice@mail.com", "alice", "alice", "Different1", false)).isTrue();
        assertThat(friendsService.getFriendList("alice").getFriends()).isEmpty();
        assertThat(authService.userLogin("alice", "Password1")).isEqualTo("Incorrect Password");
    }

    @Test
    @DisplayName("Unknown account reports an error")
    void unknownAccount() {
        assertThat(deletion.deleteAccount("ghost", null).getError()).isEqualTo("Account not found");
    }

    // ── Sign in with Apple accounts ────────────────────────────────────────────

    @Test
    @DisplayName("Apple account asks the app for a fresh Apple authorization before deleting anything")
    void appleAccountNeedsAuthorization() {
        authService.createAppleUser("me@icloud.com", "appler", "appler", APPLE_SUB);

        AuthResponse response = deletion.deleteAccount("appler", null);

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo(AccountDeletionService.APPLE_AUTHORIZATION_REQUIRED);
        assertThat(authService.userExists("appler")).isTrue();
    }

    @Test
    @DisplayName("Apple account revokes the Apple token and removes the Apple link")
    void appleAccountRevokesToken() {
        authService.createAppleUser("me@icloud.com", "appler", "appler", APPLE_SUB);
        s3.putRaw("apple-users/" + APPLE_SUB + ".json", "{\"username\":\"appler\"}".getBytes());

        AuthResponse response = deletion.deleteAccount("appler", "code-123");

        assertThat(response.isSuccess()).isTrue();
        assertThat(appleRevoker.revoked).containsExactly("refresh-code-123");
        assertThat(s3.contains("apple-users/" + APPLE_SUB + ".json")).isFalse();
        assertThat(authService.userExists("appler")).isFalse();
    }

    @Test
    @DisplayName("Authorizing with a different Apple ID is refused and nothing is deleted")
    void wrongAppleIdRefused() {
        authService.createAppleUser("me@icloud.com", "appler", "appler", APPLE_SUB);
        appleRevoker.subjectForCode = "000999.someone.else";

        AuthResponse response = deletion.deleteAccount("appler", "code-123");

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo("Please use the Apple ID connected to this account.");
        assertThat(appleRevoker.revoked).isEmpty();
        assertThat(authService.userExists("appler")).isTrue();
    }

    @Test
    @DisplayName("Without an Apple key configured, Apple accounts are still deleted (revocation skipped)")
    void appleNotConfigured() {
        appleRevoker.configured = false;
        authService.createAppleUser("me@icloud.com", "appler", "appler", APPLE_SUB);

        assertThat(deletion.deleteAccount("appler", null).isSuccess()).isTrue();
        assertThat(authService.userExists("appler")).isFalse();
    }
}
