package com.plotline.backend.ratelimit;

import java.io.IOException;
import java.util.Set;

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
 * Caps AI features (each one calls OpenAI, which costs money) at RateLimit.AI_PER_USER per
 * signed-in user. Runs after the login filter, which identifies the user, and the membership
 * check, so locked accounts don't use up their quota.
 */
@Component
@Order(4)
public class AiRateLimitFilter extends OncePerRequestFilter {

    // every endpoint that calls OpenAI (one request counts once, even if it makes several calls)
    static final Set<String> AI_ENDPOINTS = Set.of(
            "/api/llm/budget",
            "/api/llm/budget/regen",
            "/api/llm/portfolio",
            "/api/llm/portfolio/rate",
            "/api/costs/upload-receipt",
            "/api/nutrition/analyze-food",
            "/openai/string-response",
            "/api/groceryLists/estimate-grocery-cost",
            "/api/groceryLists/estimate-grocery-cost-live",
            "/api/groceryLists/generate-from-meal",
            "/api/groceryLists/generate-meal-from-list",
            "/api/groceryLists/generate-list-from-goal"
    );

    private final RateLimiter limiter;
    private final boolean enabled;

    public AiRateLimitFilter(RateLimiter limiter, @Value("${plotline.ratelimit.enabled:true}") boolean enabled) {
        this.limiter = limiter;
        this.enabled = enabled;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI().substring(request.getContextPath().length());
        return !enabled || !"POST".equals(request.getMethod()) || !AI_ENDPOINTS.contains(path);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String user = CurrentUser.get(request);
        if (user != null) {
            RateLimiter.Decision decision = limiter.tryConsume(RateLimit.AI_PER_USER, user);
            if (!decision.allowed()) {
                RateLimitResponses.tooManyRequests(response,
                        "You've reached today's limit for AI features. Try again in "
                                + RateLimitResponses.waitTime(decision.retryAfterSeconds()) + ".",
                        decision.retryAfterSeconds());
                return;
            }
        }
        chain.doFilter(request, response);
    }
}
