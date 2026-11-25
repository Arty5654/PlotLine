package com.plotline.backend.ratelimit;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import com.plotline.backend.security.CurrentUser;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * A limit on every API call, counted across every server machine:
 *   - signed in: per user and per IP, plus a tighter limit for calls that cost money or reach other
 *     people (Plaid, posts and friend requests, uploads, outside data), all in one round trip
 *   - not signed in (public pages, sign-in): per IP
 * Runs after the login filter (it needs to know who's asking); sign-in, texts and AI calls also
 * have their own limits (AuthRateLimitFilter, AiRateLimitFilter).
 */
@Component
@Order(5)
public class ApiRateLimitFilter extends OncePerRequestFilter {

    private final RateLimiter limiter;
    private final boolean enabled;

    public ApiRateLimitFilter(RateLimiter limiter, @Value("${plotline.ratelimit.enabled:true}") boolean enabled) {
        this.limiter = limiter;
        this.enabled = enabled;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !enabled || "OPTIONS".equals(request.getMethod());
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String ip = AuthRateLimitFilter.clientIp(request);
        String user = CurrentUser.get(request);
        List<RateLimiter.Check> checks = new ArrayList<>();
        checks.add(new RateLimiter.Check(RateLimit.API_PER_IP, ip));
        if (user != null) {
            checks.add(new RateLimiter.Check(RateLimit.API_PER_USER, user));
            for (RateLimit group : groups(request.getMethod(), path(request))) checks.add(new RateLimiter.Check(group, user));
        }
        RateLimiter.Decision decision = limiter.tryConsume(checks);
        if (!decision.allowed()) {
            RateLimitResponses.tooManyRequests(response,
                    "Too many requests. Try again in " + RateLimitResponses.waitTime(decision.retryAfterSeconds()) + ".",
                    decision.retryAfterSeconds());
            return;
        }
        chain.doFilter(request, response);
    }

    /** the tighter limits a call also counts toward */
    static List<RateLimit> groups(String method, String path) {
        List<RateLimit> out = new ArrayList<>();
        boolean write = "POST".equals(method) || "PUT".equals(method) || "PATCH".equals(method) || "DELETE".equals(method);
        if (path.startsWith("/api/plaid/") || path.equals("/api/plaid")) out.add(RateLimit.PLAID_PER_USER);
        if (write && (path.startsWith("/friends/") || path.equals("/chat") || path.startsWith("/chat/"))) out.add(RateLimit.SOCIAL_PER_USER);
        if ("PUT".equals(method) && path.equals("/friends/request")) out.add(RateLimit.FRIEND_REQUESTS_PER_USER);
        if (path.equals("/profile/upload-profile-pic")) out.add(RateLimit.UPLOADS_PER_USER);
        if (path.equals("/api/news") || path.equals("/api/nutrition/food-search")) out.add(RateLimit.EXTERNAL_PER_USER);
        return out;
    }

    private static String path(HttpServletRequest request) {
        String path = request.getRequestURI().substring(request.getContextPath().length());
        return path.length() > 1 && path.endsWith("/") ? path.substring(0, path.length() - 1) : path;
    }
}
