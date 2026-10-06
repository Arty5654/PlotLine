package com.plotline.backend.security;

import java.lang.reflect.Method;
import java.util.Map;

import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.HandlerMapping;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import static com.plotline.backend.util.UsernameUtils.normalize;

/**
 * Checks path variables and query/form params named in {@link ActingUser} (default "username",
 * "userId") against the signed-in user. JSON bodies are checked by {@link OwnershipBodyAdvice}.
 */
public class OwnershipInterceptor implements HandlerInterceptor {

    // an @ActingUser with all defaults, for endpoints that don't declare one
    @ActingUser
    private static void defaults() { }

    static final ActingUser DEFAULT_RULE;
    static {
        try {
            DEFAULT_RULE = OwnershipInterceptor.class.getDeclaredMethod("defaults").getAnnotation(ActingUser.class);
        } catch (NoSuchMethodException e) {
            throw new ExceptionInInitializerError(e);
        }
    }

    public static ActingUser ruleFor(Method method) {
        ActingUser rule = method.getAnnotation(ActingUser.class);
        return rule != null ? rule : DEFAULT_RULE;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        if (!(handler instanceof HandlerMethod handlerMethod) || PublicEndpoints.isPublic(request)) {
            return true;
        }

        String me = CurrentUser.get(request);
        if (me == null) {
            // fail closed: a non-public endpoint reached without the auth filter
            return reject(response, HttpServletResponse.SC_UNAUTHORIZED, "Please sign in again.");
        }

        @SuppressWarnings("unchecked")
        Map<String, String> pathVariables =
                (Map<String, String>) request.getAttribute(HandlerMapping.URI_TEMPLATE_VARIABLES_ATTRIBUTE);

        for (String name : ruleFor(handlerMethod.getMethod()).value()) {
            if (pathVariables != null && pathVariables.containsKey(name) && !me.equals(normalize(pathVariables.get(name)))) {
                return reject(response, HttpServletResponse.SC_FORBIDDEN, ForbiddenException.DEFAULT_MESSAGE);
            }
            String[] values = request.getParameterValues(name);
            if (values != null) {
                for (String value : values) {
                    if (!me.equals(normalize(value))) {
                        return reject(response, HttpServletResponse.SC_FORBIDDEN, ForbiddenException.DEFAULT_MESSAGE);
                    }
                }
            }
        }
        return true;
    }

    private static boolean reject(HttpServletResponse response, int status, String message) throws Exception {
        response.setStatus(status);
        response.setContentType("application/json");
        response.getWriter().write("{\"success\": false, \"error\": \"" + message + "\"}");
        return false;
    }
}
