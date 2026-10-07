package com.plotline.backend.ratelimit;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import static com.plotline.backend.util.UsernameUtils.normalize;

/**
 * Limits sign-in, sign-up, verification texts, code checks and password changes, by IP and by
 * the username or phone number in the request. Runs first, before any other filter.
 */
@Component
@Order(0)
public class AuthRateLimitFilter extends OncePerRequestFilter {

    private record Check(RateLimit limit, String key) { }

    private final RateLimiter limiter;
    private final boolean enabled;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public AuthRateLimitFilter(RateLimiter limiter, @Value("${plotline.ratelimit.enabled:true}") boolean enabled) {
        this.limiter = limiter;
        this.enabled = enabled;
    }

    private static final Set<String> LIMITED_PATHS = Set.of(
            "/auth/signin", "/auth/google-signin", "/auth/apple-signin", "/auth/signup",
            "/sms/send-verification", "/sms/verify-code", "/auth/change-password-code", "/auth/change-password");

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !enabled || !"POST".equals(request.getMethod()) || !LIMITED_PATHS.contains(path(request));
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        CachedBodyRequest cached = new CachedBodyRequest(request);
        JsonNode body = readJson(cached.body());
        String ip = clientIp(request);

        List<Check> checks = new ArrayList<>();
        switch (path(request)) {
            case "/auth/signin" -> {
                checks.add(new Check(RateLimit.SIGN_IN_PER_IP, ip));
                addIfPresent(checks, RateLimit.SIGN_IN_PER_USERNAME, normalize(text(body, "username")));
            }
            case "/auth/google-signin", "/auth/apple-signin" -> checks.add(new Check(RateLimit.SOCIAL_SIGN_IN_PER_IP, ip));
            case "/auth/signup" -> checks.add(new Check(RateLimit.SIGN_UP_PER_IP, ip));
            case "/sms/send-verification" -> {
                checks.add(new Check(RateLimit.TEXT_PER_IP, ip));
                addIfPresent(checks, RateLimit.TEXT_PER_PHONE, text(body, "toNumber").replaceAll("\\D", ""));
            }
            case "/sms/verify-code", "/auth/change-password-code" ->
                    addIfPresent(checks, RateLimit.CODE_CHECK_PER_USERNAME, normalize(text(body, "username")));
            case "/auth/change-password" ->
                    addIfPresent(checks, RateLimit.CHANGE_PASSWORD_PER_USERNAME, normalize(text(body, "username")));
            default -> { }
        }

        for (Check check : checks) {
            RateLimiter.Decision decision = limiter.tryConsume(check.limit(), check.key());
            if (!decision.allowed()) {
                RateLimitResponses.tooManyRequests(response,
                        "Too many attempts. Try again in " + RateLimitResponses.waitTime(decision.retryAfterSeconds()) + ".",
                        decision.retryAfterSeconds());
                return;
            }
        }
        chain.doFilter(cached, response);
    }

    /** The caller's IP. Fly's proxy puts the real one in Fly-Client-IP; locally it's the socket address. */
    static String clientIp(HttpServletRequest request) {
        String fly = request.getHeader("Fly-Client-IP");
        return fly != null && !fly.isBlank() ? fly.trim() : request.getRemoteAddr();
    }

    private static String path(HttpServletRequest request) {
        String path = request.getRequestURI().substring(request.getContextPath().length());
        return path.length() > 1 && path.endsWith("/") ? path.substring(0, path.length() - 1) : path;
    }

    private JsonNode readJson(byte[] body) {
        try {
            return body.length == 0 ? null : objectMapper.readTree(body);
        } catch (IOException e) {
            return null;
        }
    }

    private static String text(JsonNode body, String field) {
        return body != null && body.hasNonNull(field) ? body.get(field).asText() : "";
    }

    private static void addIfPresent(List<Check> checks, RateLimit limit, String key) {
        if (key != null && !key.isBlank()) checks.add(new Check(limit, key));
    }
}
