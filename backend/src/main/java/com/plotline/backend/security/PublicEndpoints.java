package com.plotline.backend.security;

import java.util.Set;

import jakarta.servlet.http.HttpServletRequest;

/** The only endpoints that work without a login token. Everything else requires one. */
public final class PublicEndpoints {

    private PublicEndpoints() {}

    private static final Set<String> PUBLIC_POSTS = Set.of(
            "/auth/signin",
            "/auth/signup",
            "/auth/google-signin",
            "/auth/apple-signin",
            "/auth/change-password-code",   // forgot-password flow (proves ownership with an SMS code)
            "/sms/send-verification",       // sends that code
            "/api/payments/apple/notifications" // from Apple's servers; checked by Apple's signature instead
    );

    private static final Set<String> PUBLIC_GETS = Set.of(
            "/invite",
            "/plaid-oauth",
            "/terms",
            "/privacy"
    );

    // what an account can still reach while it owes a setup step (accepting the terms or
    // verifying a phone): finishing that step, refreshing its session, or deleting itself
    private static final Set<String> SETUP_POSTS = Set.of(
            "/auth/refresh",
            "/auth/accept-terms",
            "/auth/delete-account",
            "/sms/verify-code"
    );

    public static boolean isAllowedDuringSetup(HttpServletRequest request) {
        return "POST".equals(request.getMethod()) && SETUP_POSTS.contains(normalizedPath(request));
    }

    // what an account can still reach without an active membership: the setup steps above,
    // checking its membership, and linking an App Store purchase (the paywall in the app)
    private static final Set<String> NO_MEMBERSHIP_POSTS = Set.of(
            "/api/payments/apple/sync"
    );
    private static final String MEMBERSHIP_STATUS_PREFIX = "/api/payments/status/";

    public static boolean isAllowedWithoutMembership(HttpServletRequest request) {
        if (isAllowedDuringSetup(request)) return true;
        String path = normalizedPath(request);
        if ("POST".equals(request.getMethod())) return NO_MEMBERSHIP_POSTS.contains(path);
        return "GET".equals(request.getMethod()) && path.startsWith(MEMBERSHIP_STATUS_PREFIX)
                && path.indexOf('/', MEMBERSHIP_STATUS_PREFIX.length()) < 0;
    }

    private static String normalizedPath(HttpServletRequest request) {
        String path = request.getRequestURI();
        String contextPath = request.getContextPath();
        if (contextPath != null && !contextPath.isEmpty() && path.startsWith(contextPath)) {
            path = path.substring(contextPath.length());
        }
        if (path.length() > 1 && path.endsWith("/")) {
            path = path.substring(0, path.length() - 1);
        }
        return path;
    }

    public static boolean isPublic(HttpServletRequest request) {
        String path = request.getRequestURI();
        String contextPath = request.getContextPath();
        if (contextPath != null && !contextPath.isEmpty() && path.startsWith(contextPath)) {
            path = path.substring(contextPath.length());
        }
        if (path.length() > 1 && path.endsWith("/")) {
            path = path.substring(0, path.length() - 1);
        }
        String method = request.getMethod();

        if (path.startsWith("/.well-known/") || path.equals("/error")) return true;
        if ("POST".equals(method) && PUBLIC_POSTS.contains(path)) return true;
        if ("GET".equals(method) && PUBLIC_GETS.contains(path)) return true;
        return false;
    }
}
