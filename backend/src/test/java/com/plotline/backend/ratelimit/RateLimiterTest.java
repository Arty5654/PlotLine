package com.plotline.backend.ratelimit;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;

class RateLimiterTest {

    private final FakeClock clock = new FakeClock();
    private final RateLimiter limiter = new RateLimiter(clock);

    private int allowedInARow(RateLimit limit, String key, int attempts) {
        int allowed = 0;
        for (int i = 0; i < attempts; i++) if (limiter.tryConsume(limit, key).allowed()) allowed++;
        return allowed;
    }

    @Test
    @DisplayName("Allows up to the limit, then refuses with how long to wait")
    void limitThenRefuse() {
        assertThat(allowedInARow(RateLimit.SIGN_IN_PER_USERNAME, "alex", 10)).isEqualTo(10);

        RateLimiter.Decision refused = limiter.tryConsume(RateLimit.SIGN_IN_PER_USERNAME, "alex");
        assertThat(refused.allowed()).isFalse();
        assertThat(refused.retryAfterSeconds()).isBetween(1L, 15 * 60L);
    }

    @Test
    @DisplayName("The full allowance comes back once the window has passed")
    void resetsAfterWindow() {
        allowedInARow(RateLimit.SIGN_IN_PER_USERNAME, "alex", 10);
        assertThat(limiter.tryConsume(RateLimit.SIGN_IN_PER_USERNAME, "alex").allowed()).isFalse();

        clock.advance(Duration.ofMinutes(15));

        assertThat(allowedInARow(RateLimit.SIGN_IN_PER_USERNAME, "alex", 10)).isEqualTo(10);
    }

    @Test
    @DisplayName("Different people and different limits are counted separately")
    void separateCounts() {
        allowedInARow(RateLimit.SIGN_IN_PER_USERNAME, "alex", 10);

        assertThat(limiter.tryConsume(RateLimit.SIGN_IN_PER_USERNAME, "sam").allowed()).isTrue();
        assertThat(limiter.tryConsume(RateLimit.CHANGE_PASSWORD_PER_USERNAME, "alex").allowed()).isTrue();
    }

    @Test
    @DisplayName("Texts to one phone: 3 per 10 minutes and 10 per day")
    void textLimits() {
        int sent = 0;
        for (int round = 0; round < 6; round++) {          // an hour of trying every 10 minutes
            sent += allowedInARow(RateLimit.TEXT_PER_PHONE, "5555550123", 5);
            clock.advance(Duration.ofMinutes(10));
        }
        assertThat(sent).isEqualTo(10);                     // the daily cap kicks in

        clock.advance(Duration.ofDays(1));
        assertThat(limiter.tryConsume(RateLimit.TEXT_PER_PHONE, "5555550123").allowed()).isTrue();
    }

    @Test
    @DisplayName("AI features: 50 per user per day")
    void aiDailyCap() {
        assertThat(allowedInARow(RateLimit.AI_PER_USER, "alex", 60)).isEqualTo(50);
        RateLimiter.Decision refused = limiter.tryConsume(RateLimit.AI_PER_USER, "alex");
        assertThat(refused.retryAfterSeconds()).isGreaterThan(60 * 60L);

        clock.advance(Duration.ofDays(1));
        assertThat(limiter.tryConsume(RateLimit.AI_PER_USER, "alex").allowed()).isTrue();
    }

    @Test
    @DisplayName("Wait times read naturally")
    void waitTimes() {
        assertThat(RateLimitResponses.waitTime(5)).isEqualTo("1 minute");
        assertThat(RateLimitResponses.waitTime(7 * 60)).isEqualTo("7 minutes");
        assertThat(RateLimitResponses.waitTime(5 * 3600)).isEqualTo("5 hours");
    }
}
