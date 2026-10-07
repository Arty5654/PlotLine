package com.plotline.backend.ratelimit;

import java.time.Duration;
import java.util.List;

/**
 * Every rate limit in the app. A request is refused once any of its limits is used up.
 * Change the numbers here to tune them.
 */
public enum RateLimit {
    // password sign-in: per IP, and per username so one account can't be guessed at from many IPs
    SIGN_IN_PER_IP(window(10, Duration.ofMinutes(1))),
    SIGN_IN_PER_USERNAME(window(10, Duration.ofMinutes(15))),

    // Apple / Google sign-in (already protected by Apple and Google)
    SOCIAL_SIGN_IN_PER_IP(window(20, Duration.ofMinutes(1))),

    SIGN_UP_PER_IP(window(5, Duration.ofHours(1))),

    // verification texts cost money per send
    TEXT_PER_PHONE(window(3, Duration.ofMinutes(10)), window(10, Duration.ofDays(1))),
    TEXT_PER_IP(window(10, Duration.ofHours(1))),

    // checking a texted code (phone verification, password reset)
    CODE_CHECK_PER_USERNAME(window(5, Duration.ofMinutes(10))),

    CHANGE_PASSWORD_PER_USERNAME(window(5, Duration.ofMinutes(15))),

    // AI features cost OpenAI money per call
    AI_PER_USER(window(50, Duration.ofDays(1)));

    record Window(long requests, Duration period) { }

    private final List<Window> windows;

    RateLimit(Window... windows) {
        this.windows = List.of(windows);
    }

    List<Window> windows() {
        return windows;
    }

    private static Window window(long requests, Duration period) {
        return new Window(requests, period);
    }
}
