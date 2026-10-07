package com.plotline.backend.ratelimit;

import java.io.IOException;

import jakarta.servlet.http.HttpServletResponse;

final class RateLimitResponses {

    private RateLimitResponses() {}

    /** 429 with a Retry-After header and a message the app shows as-is. */
    static void tooManyRequests(HttpServletResponse response, String message, long retryAfterSeconds) throws IOException {
        response.setStatus(429);
        response.setHeader("Retry-After", String.valueOf(retryAfterSeconds));
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        String safe = message.replace("\\", "\\\\").replace("\"", "\\\"");
        response.getWriter().write("{\"success\": false, \"error\": \"" + safe + "\"}");
    }

    /** "1 minute", "7 minutes", "3 hours" */
    static String waitTime(long seconds) {
        long minutes = Math.max(1, (seconds + 59) / 60);
        if (minutes < 120) return minutes + (minutes == 1 ? " minute" : " minutes");
        long hours = (minutes + 59) / 60;
        return hours + " hours";
    }
}
