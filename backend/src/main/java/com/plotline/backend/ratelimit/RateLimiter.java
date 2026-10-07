package com.plotline.backend.ratelimit;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;

import io.github.bucket4j.Bucket;
import io.github.bucket4j.ConsumptionProbe;
import io.github.bucket4j.TimeMeter;
import io.github.bucket4j.local.LocalBucketBuilder;

/**
 * Counts requests per (limit, key) in memory. Entries nobody has touched for a day and a bit are
 * dropped, so memory stays small. Counts live on this machine only; with several machines,
 * swap in Bucket4j's Redis support so they share counts.
 */
@Component
public class RateLimiter {

    /** Whether the request may go ahead, and if not, how long until it can. */
    public record Decision(boolean allowed, long retryAfterSeconds) { }

    private final TimeMeter clock;
    private final Cache<String, Bucket> buckets = Caffeine.newBuilder()
            .expireAfterAccess(Duration.ofHours(25))
            .maximumSize(200_000)
            .build();

    @Autowired
    public RateLimiter() {
        this(TimeMeter.SYSTEM_MILLISECONDS);
    }

    // for tests: a clock they control
    RateLimiter(TimeMeter clock) {
        this.clock = clock;
    }

    public Decision tryConsume(RateLimit limit, String key) {
        Bucket bucket = buckets.get(limit.name() + ":" + key, k -> newBucket(limit));
        ConsumptionProbe probe = bucket.tryConsumeAndReturnRemaining(1);
        if (probe.isConsumed()) {
            return new Decision(true, 0);
        }
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
