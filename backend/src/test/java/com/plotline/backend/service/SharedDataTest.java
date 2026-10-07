package com.plotline.backend.service;

import com.plotline.backend.accounts.AccountDirectory;
import com.plotline.backend.accounts.S3DataImport;
import com.plotline.backend.dto.FriendPost;
import com.plotline.backend.membership.Membership;
import com.plotline.backend.membership.MembershipService;
import com.plotline.backend.testsupport.InMemoryS3Client;
import com.plotline.backend.testsupport.TestDatabase;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import javax.sql.DataSource;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Audit #7: the user list, email index and feed used to be single S3 files rewritten on every
 * change, so changes made at the same moment erased each other. Now they're Postgres rows.
 */
class SharedDataTest {

    private InMemoryS3Client s3;
    private DataSource database;
    private JdbcTemplate jdbc;
    private AuthService authService;
    private FriendsFeedService feed;
    private MembershipService memberships;

    @BeforeEach
    void setUp() {
        s3 = new InMemoryS3Client();
        database = TestDatabase.newDatabase();
        jdbc = new JdbcTemplate(database);
        authService = new AuthService(s3, null, "test-jwt-secret", new AccountDirectory(jdbc));
        feed = new FriendsFeedService(s3, jdbc);
        memberships = new MembershipService(jdbc, authService, 1000, 7);
    }

    private static <T> List<T> atOnce(int count, java.util.function.IntFunction<Callable<T>> task) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(count);
        try {
            List<Future<T>> futures = new ArrayList<>();
            for (int i = 0; i < count; i++) futures.add(pool.submit(task.apply(i)));
            List<T> results = new ArrayList<>();
            for (Future<T> future : futures) results.add(future.get());
            return results;
        } finally {
            pool.shutdown();
        }
    }

    @Test
    @DisplayName("20 sign-ups at the same moment: every account is kept")
    void simultaneousSignUps() throws Exception {
        List<Boolean> created = atOnce(20, i -> () ->
                authService.createUser("555", "user" + i + "@mail.com", "user" + i, "user" + i, "Password1", false));

        assertThat(created).containsOnly(true);
        assertThat(jdbc.queryForObject("select count(*) from accounts", Integer.class)).isEqualTo(20);
        assertThat(authService.searchUsernames("user", "nobody")).hasSize(20);
    }

    @Test
    @DisplayName("Two sign-ups with the same email at the same moment: only one gets it")
    void sameEmailOnce() throws Exception {
        List<Boolean> created = atOnce(10, i -> () ->
                authService.createUser("555", "shared@mail.com", "person" + i, "person" + i, "Password1", false));

        assertThat(created.stream().filter(ok -> ok)).hasSize(1);
        assertThat(authService.usernameForEmail("SHARED@mail.com")).startsWith("person");
    }

    @Test
    @DisplayName("20 likes and comments on one post at the same moment: none are lost")
    void simultaneousLikes() throws Exception {
        FriendPost post = new FriendPost();
        post.setId(UUID.randomUUID());
        post.setUsername("author");
        post.setComment("Ran a 5k");
        assertThat(feed.addPostToFeed(post)).isTrue();

        atOnce(20, i -> () -> feed.toggleLike("fan" + i, post.getId()) && feed.addComment("fan" + i, post.getId(), "nice"));

        FriendPost saved = feed.getFriendsFeed("author").get(0);
        assertThat(saved.getLikedBy()).hasSize(20);
        assertThat(saved.getComments()).hasSize(20);
    }

    @Test
    @DisplayName("Search: names containing the text, ones that start with it first")
    void search() {
        authService.createUser("555", "a@mail.com", "zoealice", "ZoeAlice", "Password1", false);
        authService.createUser("555", "b@mail.com", "alicew", "AliceW", "Password1", false);
        authService.createUser("555", "c@mail.com", "bob", "bob", "Password1", false);

        assertThat(authService.searchUsernames("ALI", "bob")).containsExactly("AliceW", "ZoeAlice");
        assertThat(authService.searchUsernames("ali", "alicew")).containsExactly("ZoeAlice");
        assertThat(authService.searchUsernames("", "bob")).isEmpty();
    }

    @Test
    @DisplayName("First startup copies the old S3 files into the database, once")
    void importsOldFiles() throws Exception {
        // what S3 looks like today, including an account missing from all-users.json (a lost update)
        s3.putRaw("all-users.json", "[\"Bob\", \"amy\"]".getBytes());
        s3.putRaw("email-index.json", "{\"amy@mail.com\": \"amy\", \"bob@mail.com\": \"bob\"}".getBytes());
        s3.putRaw("users/amy/account.json", "{\"username\":\"amy\",\"displayUsername\":\"amy\",\"email\":\"amy@mail.com\",\"createdAt\":2000}".getBytes());
        s3.putRaw("users/bob/account.json", "{\"username\":\"bob\",\"displayUsername\":\"Bob\",\"email\":\"Bob@mail.com\",\"createdAt\":1000}".getBytes());
        s3.putRaw("users/lost/account.json", "{\"username\":\"lost\",\"displayUsername\":\"Lost\",\"email\":\"lost@mail.com\",\"createdAt\":500}".getBytes());
        s3.putRaw("users/bob/subscription.json", "{\"plan\":\"lifetime\",\"monthlyPrice\":0.0}".getBytes());
        s3.putRaw("app-store/subscriptions/777.json", "{\"username\":\"amy\"}".getBytes());
        String postId = UUID.randomUUID().toString();
        s3.putRaw("friends-feed/posts.json", ("[{\"id\":\"" + postId + "\",\"username\":\"Bob\",\"comment\":\"hi\","
                + "\"likedBy\":[\"amy\"],\"comments\":[\"amy: yay\"]}]").getBytes());

        S3DataImport importer = new S3DataImport(s3, jdbc, new TransactionTemplate(new DataSourceTransactionManager(database)), feed, memberships);
        importer.importAll();
        importer.importAll(); // later startups do nothing

        // sign-up order: all-users.json first, then accounts it lost
        assertThat(jdbc.queryForList("select username from accounts order by signup_number", String.class))
                .containsExactly("bob", "amy", "lost");
        assertThat(authService.signupRank("amy")).isEqualTo(2L);
        assertThat(authService.usernameForEmail("bob@mail.com")).isEqualTo("bob");
        assertThat(authService.usernameForEmail("lost@mail.com")).isEqualTo("lost");

        FriendPost post = feed.getFriendsFeed("bob").get(0);
        assertThat(post.getComment()).isEqualTo("hi");
        assertThat(post.getLikedBy()).containsExactly("amy");
        assertThat(post.getComments()).containsExactly("amy: yay");

        assertThat(memberships.membership("bob").getPlan()).isEqualTo(Membership.LIFETIME);
        assertThat(jdbc.queryForObject("select username from app_store_subscriptions where original_transaction_id = '777'", String.class))
                .isEqualTo("amy");
        assertThat(jdbc.queryForObject("select count(*) from feed_posts", Integer.class)).isEqualTo(1);
    }
}
