package com.plotline.backend.security;

import java.io.IOException;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import com.plotline.backend.ratelimit.AuthRateLimitFilter;
import com.plotline.backend.ratelimit.RateLimit;
import com.plotline.backend.ratelimit.RateLimitResponses;
import com.plotline.backend.ratelimit.RateLimiter;
import com.plotline.backend.service.AuthService;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * Requires a valid login token (Authorization: Bearer ...) on every non-public endpoint and
 * records who the caller is. Runs after the API key check.
 */
@Component
@Order(2)
public class JwtAuthFilter extends OncePerRequestFilter {

    private final AuthService authService;

    private final RateLimiter limiter;
    private final boolean limited;

    public JwtAuthFilter(AuthService authService, org.springframework.beans.factory.ObjectProvider<RateLimiter> limiter,
                         @Value("${plotline.ratelimit.enabled:true}") boolean limited) {
        this.authService = authService;
        this.limiter = limiter.getIfAvailable();   // none in web-layer tests
        this.limited = limited && this.limiter != null;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return PublicEndpoints.isPublic(request);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        String token = header != null && header.startsWith("Bearer ") ? header.substring(7).trim() : null;
        String username = authService.authenticatedUsername(token);

        if (username == null) {
            // a bad or expired token: counted per IP, so guessing tokens gets cut off
            if (limited) {
                RateLimiter.Decision decision = limiter.tryConsume(RateLimit.BAD_TOKEN_PER_IP, AuthRateLimitFilter.clientIp(request));
                if (!decision.allowed()) {
                    RateLimitResponses.tooManyRequests(response,
                            "Too many requests. Try again in " + RateLimitResponses.waitTime(decision.retryAfterSeconds()) + ".",
                            decision.retryAfterSeconds());
                    return;
                }
            }
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.setContentType("application/json");
            response.getWriter().write("{\"success\": false, \"error\": \"Please sign in again.\"}");
            return;
        }

        // accounts that haven't accepted the terms or verified their phone can only finish that step
        String pendingStep = authService.pendingAccountStep(username);
        if (pendingStep != null && !PublicEndpoints.isAllowedDuringSetup(request)) {
            response.setStatus(HttpServletResponse.SC_FORBIDDEN);
            response.setContentType("application/json");
            response.getWriter().write("{\"success\": false, \"error\": \"" + pendingStep + "\"}");
            return;
        }

        request.setAttribute(CurrentUser.ATTRIBUTE, username);
        filterChain.doFilter(request, response);
    }
}
