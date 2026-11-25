package com.plotline.backend.ratelimit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;

import com.plotline.backend.testsupport.TestDatabase;

import io.github.bucket4j.TimeMeter;

/** Rate limits counted in Postgres: several server machines share the same counts. */
class SharedCountsTest {

    private static JdbcTemplate jdbc;

    @BeforeAll
    static void database() {
        jdbc = new JdbcTemplate(TestDatabase.newDatabase());
    }

    @SuppressWarnings("unchecked")
    private static SharedCounts shared(JdbcTemplate jdbc) {
        ObjectProvider<JdbcTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(jdbc);
        return new SharedCounts(provider, "shared");
    }

    /** a server machine: its own memory, the shared database */
    private static RateLimiter machine() {
        return new RateLimiter(TimeMeter.SYSTEM_MILLISECONDS, shared(jdbc));
    }

    @Test
    @DisplayName("Two machines share one count: 60 bad tokens per IP across both, the 61st is refused on either")
    void twoMachines() {
        RateLimiter a = machine(), b = machine();
        for (int i = 0; i < 30; i++) {
            assertThat(a.tryConsume(RateLimit.BAD_TOKEN_PER_IP, "203.0.113.7").allowed()).isTrue();
            assertThat(b.tryConsume(RateLimit.BAD_TOKEN_PER_IP, "203.0.113.7").allowed()).isTrue();
        }
        RateLimiter.Decision refused = a.tryConsume(RateLimit.BAD_TOKEN_PER_IP, "203.0.113.7");
        assertThat(refused.allowed()).isFalse();
        assertThat(refused.retryAfterSeconds()).isBetween(1L, 60L);
        assertThat(b.tryConsume(RateLimit.BAD_TOKEN_PER_IP, "203.0.113.7").allowed()).isFalse();
        // another IP has its own count
        assertThat(b.tryConsume(RateLimit.BAD_TOKEN_PER_IP, "198.51.100.1").allowed()).isTrue();
    }

    @Test
    @DisplayName("Requests at the same moment on many machines can't slip past the limit")
    void concurrent() throws Exception {
        List<RateLimiter> machines = List.of(machine(), machine(), machine(), machine());
        ExecutorService pool = Executors.newFixedThreadPool(8);
        List<Future<Boolean>> results = new ArrayList<>();
        for (int i = 0; i < 100; i++) {
            RateLimiter m = machines.get(i % machines.size());
            results.add(pool.submit(() -> m.tryConsume(RateLimit.FRIEND_REQUESTS_PER_USER, "racer").allowed()));
        }
        int allowed = 0;
        for (Future<Boolean> f : results) if (f.get()) allowed++;
        pool.shutdown();
        assertThat(allowed).isEqualTo(30);   // the daily friend-request limit, exactly
    }

    @Test
    @DisplayName("Several limits in one round trip: any one used up refuses the request; each window has its own row")
    void severalLimits() {
        RateLimiter m = machine();
        List<RateLimiter.Check> checks = List.of(new RateLimiter.Check(RateLimit.API_PER_USER, "multi"),
                new RateLimiter.Check(RateLimit.UPLOADS_PER_USER, "multi"));
        for (int i = 0; i < 20; i++) assertThat(m.tryConsume(checks).allowed()).isTrue();
        assertThat(m.tryConsume(checks).allowed()).isFalse();               // uploads: 20 an hour
        assertThat(m.tryConsume(RateLimit.API_PER_USER, "multi").allowed()).isTrue();   // the rest still works
        // API_PER_USER has a minute and an hour window
        Integer rows = jdbc.queryForObject("select count(*) from rate_limit_hits where bucket like 'API_PER_USER:multi:%'", Integer.class);
        assertThat(rows).isEqualTo(2);
    }

    @Test
    @DisplayName("Finished windows are deleted")
    void cleanUp() {
        jdbc.update("insert into rate_limit_hits (bucket, window_start, hits, expires_at) values ('OLD:x:60', 0, 5, now() - interval '1 hour')");
        shared(jdbc).cleanUp();
        assertThat(jdbc.queryForObject("select count(*) from rate_limit_hits where bucket = 'OLD:x:60'", Integer.class)).isZero();
    }

    @Test
    @DisplayName("If the database can't be reached, each machine counts on its own instead of blocking requests")
    void databaseDown() {
        JdbcTemplate broken = new JdbcTemplate(new org.springframework.jdbc.datasource.DriverManagerDataSource(
                "jdbc:postgresql://127.0.0.1:1/none"));
        RateLimiter m = new RateLimiter(TimeMeter.SYSTEM_MILLISECONDS, shared(broken));
        for (int i = 0; i < 20; i++) assertThat(m.tryConsume(RateLimit.UPLOADS_PER_USER, "offline").allowed()).isTrue();
        assertThat(m.tryConsume(RateLimit.UPLOADS_PER_USER, "offline").allowed()).isFalse();
    }

    @Test
    @DisplayName("Which calls get a tighter limit")
    void groups() {
        assertThat(ApiRateLimitFilter.groups("GET", "/api/plaid/accounts")).containsExactly(RateLimit.PLAID_PER_USER);
        assertThat(ApiRateLimitFilter.groups("PUT", "/friends/request"))
                .containsExactly(RateLimit.SOCIAL_PER_USER, RateLimit.FRIEND_REQUESTS_PER_USER);
        assertThat(ApiRateLimitFilter.groups("POST", "/chat")).containsExactly(RateLimit.SOCIAL_PER_USER);
        assertThat(ApiRateLimitFilter.groups("GET", "/chat/get-feed")).isEmpty();
        assertThat(ApiRateLimitFilter.groups("POST", "/profile/upload-profile-pic")).containsExactly(RateLimit.UPLOADS_PER_USER);
        assertThat(ApiRateLimitFilter.groups("GET", "/api/news")).containsExactly(RateLimit.EXTERNAL_PER_USER);
        assertThat(ApiRateLimitFilter.groups("GET", "/api/plan/alex")).isEmpty();
    }
}
