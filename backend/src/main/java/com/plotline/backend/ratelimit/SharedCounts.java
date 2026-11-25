package com.plotline.backend.ratelimit;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/**
 * Rate-limit counts in Postgres, so every server machine counts the same requests: a user who is at
 * their limit on one machine is at it on all of them. Each window is a fixed slice of time (this
 * minute, this hour, today in UTC); one statement adds the request to every window it counts in and
 * returns the new counts, so concurrent requests on different machines can't both slip through.
 *
 * Off when there's no database (or plotline.ratelimit.store=local): each machine then counts alone.
 */
@Component
public class SharedCounts {
    private static final Logger log = LoggerFactory.getLogger(SharedCounts.class);

    /** every this many requests (per machine), windows that are over are deleted */
    static final long CLEANUP_EVERY = 2_000;

    private final JdbcTemplate jdbc;
    private final AtomicLong calls = new AtomicLong();

    public SharedCounts(ObjectProvider<JdbcTemplate> jdbc, @Value("${plotline.ratelimit.store:shared}") String store) {
        this.jdbc = "shared".equalsIgnoreCase(store) ? jdbc.getIfAvailable() : null;
    }

    public boolean enabled() { return jdbc != null; }

    private record Window(String bucket, long start, long end, long limit) { }

    /** counts this request in every window of every check; refused if any is over its limit */
    RateLimiter.Decision hit(List<RateLimiter.Check> checks, Instant now) {
        long nowSec = now.getEpochSecond();
        // one row per window (a limit and key that appear twice are counted once)
        Map<String, Window> windows = new LinkedHashMap<>();
        for (RateLimiter.Check check : checks) {
            for (RateLimit.Window w : check.limit().windows()) {
                long period = Math.max(1, w.period().toSeconds());
                long start = nowSec - Math.floorMod(nowSec, period);
                String bucket = check.limit().name() + ":" + check.key() + ":" + period;
                windows.putIfAbsent(bucket + "@" + start, new Window(bucket, start, start + period, w.requests()));
            }
        }
        if (windows.isEmpty()) return RateLimiter.ALLOWED;

        StringBuilder sql = new StringBuilder("insert into rate_limit_hits (bucket, window_start, hits, expires_at) values ");
        List<Object> args = new ArrayList<>();
        int i = 0;
        for (Window w : windows.values()) {
            if (i++ > 0) sql.append(", ");
            sql.append("(?, ?, 1, ?)");
            args.add(w.bucket());
            args.add(w.start());
            args.add(Timestamp.from(Instant.ofEpochSecond(w.end())));
        }
        sql.append(" on conflict (bucket, window_start) do update set hits = rate_limit_hits.hits + 1")
           .append(" returning bucket, window_start, hits");

        Map<String, Long> hits = new HashMap<>();
        jdbc.query(sql.toString(), rs -> {
            hits.put(rs.getString(1) + "@" + rs.getLong(2), rs.getLong(3));
        }, args.toArray());

        long retryAfter = 0;
        for (var e : windows.entrySet()) {
            long count = hits.getOrDefault(e.getKey(), 0L);
            if (count > e.getValue().limit()) retryAfter = Math.max(retryAfter, e.getValue().end() - nowSec);
        }
        if (calls.incrementAndGet() % CLEANUP_EVERY == 0) cleanUp();
        return retryAfter > 0 ? new RateLimiter.Decision(false, Math.max(1, retryAfter)) : RateLimiter.ALLOWED;
    }

    /** windows that are over */
    void cleanUp() {
        try {
            int gone = jdbc.update("delete from rate_limit_hits where expires_at < now()");
            if (gone > 0) log.debug("Deleted {} finished rate-limit windows", gone);
        } catch (Exception e) {
            log.warn("Couldn't clean up rate-limit windows: {}", e.getMessage());
        }
    }
}
