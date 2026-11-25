package com.plotline.backend.ratelimit;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;

import io.github.bucket4j.Bucket;
import io.github.bucket4j.ConsumptionProbe;
import io.github.bucket4j.TimeMeter;
import io.github.bucket4j.local.LocalBucketBuilder;

/**
 * Counts requests per (limit, key). With a database ({@link SharedCounts}) the counts are shared by
 * every server machine. If the database can't be reached, or there is none (tests, local runs), this
 * machine counts in memory instead, so a database hiccup never blocks the app or drops all limits.
 */
@Component
public class RateLimiter {
    private static final Logger log = LoggerFactory.getLogger(RateLimiter.class);

    /** Whether the request may go ahead, and if not, how long until it can. */
    public record Decision(boolean allowed, long retryAfterSeconds) { }

    /** one limit for one key (a user, an IP, a phone number) */
    public record Check(RateLimit limit, String key) { }

    static final Decision ALLOWED = new Decision(true, 0);

    private final TimeMeter clock;
    private final SharedCounts shared;      // null: this machine only
    private final AtomicLong lastWarning = new AtomicLong();
    private final Cache<String, Bucket> buckets = Caffeine.newBuilder()
            .expireAfterAccess(Duration.ofHours(25))
            .maximumSize(200_000)
            .build();

    @Autowired
    public RateLimiter(SharedCounts shared) {
        this(TimeMeter.SYSTEM_MILLISECONDS, shared != null && shared.enabled() ? shared : null);
    }

    // for tests: a clock they control, counted in memory
    RateLimiter(TimeMeter clock) {
        this(clock, null);
    }

    RateLimiter(TimeMeter clock, SharedCounts shared) {
        this.clock = clock;
        this.shared = shared;
    }

    /** whether the counts are shared by every machine (else this machine only) */
    public boolean isShared() { return shared != null; }

    public Decision tryConsume(RateLimit limit, String key) {
        return tryConsume(List.of(new Check(limit, key)));
    }

    /** counts the request against every check; refused if any is used up (the longest wait) */
    public Decision tryConsume(List<Check> checks) {
        if (checks.isEmpty()) return ALLOWED;
        if (shared != null) {
            try {
                return shared.hit(checks, Instant.now());
            } catch (Exception e) {
                // at most one warning a minute, then this machine's own counts
                long now = System.currentTimeMillis(), last = lastWarning.get();
                if (now - last > 60_000 && lastWarning.compareAndSet(last, now)) {
                    log.warn("Shared rate limits unavailable, counting on this machine: {}", e.getMessage());
                }
            }
        }
        Decision refused = null;
        for (Check check : checks) {
            Decision d = local(check);
            if (!d.allowed() && (refused == null || d.retryAfterSeconds() > refused.retryAfterSeconds())) refused = d;
        }
        return refused != null ? refused : ALLOWED;
    }

    private Decision local(Check check) {
        Bucket bucket = buckets.get(check.limit().name() + ":" + check.key(), k -> newBucket(check.limit()));
        ConsumptionProbe probe = bucket.tryConsumeAndReturnRemaining(1);
        if (probe.isConsumed()) return ALLOWED;
        long seconds = TimeUnit.NANOSECONDS.toSeconds(probe.getNanosToWaitForRefill());
        return new Decision(false, Math.max(1, seconds));
    }

    private Bucket newBucket(RateLimit limit) {
        LocalBucketBuilder builder = Bucket.builder().withCustomTimePrecision(clock);
        for (RateLimit.Window window : limit.windows()) {
            // fixed windows: the full allowance comes back once the window has passed
            builder.addLimit(b -> b.capacity(window.requests()).refillIntervally(window.requests(), window.period()));
        }
        return builder.build();
    }
}
