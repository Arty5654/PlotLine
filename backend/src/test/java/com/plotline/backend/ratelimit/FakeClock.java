package com.plotline.backend.ratelimit;

import java.time.Duration;

import io.github.bucket4j.TimeMeter;

/** A clock tests can move forward instead of waiting. */
class FakeClock implements TimeMeter {
    private long nanos = 1_000_000_000L;

    @Override public long currentTimeNanos() { return nanos; }
    @Override public boolean isWallClockBased() { return false; }

    void advance(Duration duration) {
        nanos += duration.toNanos();
    }
}
