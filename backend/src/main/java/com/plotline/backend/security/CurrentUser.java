package com.plotline.backend.security;

import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;

import jakarta.servlet.http.HttpServletRequest;

import static com.plotline.backend.util.UsernameUtils.normalize;

/** The signed-in user for the current request, as set by {@link JwtAuthFilter}. */
public final class CurrentUser {

    public static final String ATTRIBUTE = "plotline.authenticatedUser";

    private CurrentUser() {}

    public static String get(HttpServletRequest request) {
        Object value = request.getAttribute(ATTRIBUTE);
        return value instanceof String ? (String) value : null;
    }

    /** normalized username of the signed-in user; throws 403 if there is none */
    public static String require() {
        Object value = RequestContextHolder.currentRequestAttributes()
                .getAttribute(ATTRIBUTE, RequestAttributes.SCOPE_REQUEST);
        if (!(value instanceof String username)) {
            throw new ForbiddenException("Please sign in again.");
        }
        return username;
    }

    public static boolean is(String username) {
        return username != null && normalize(username).equals(require());
    }

    /** throws 403 unless the given username is the signed-in user */
    public static void check(String username) {
        if (!is(username)) {
            throw new ForbiddenException();
        }
    }
}
