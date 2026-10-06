package com.plotline.backend.security;

import java.lang.reflect.Method;
import java.lang.reflect.RecordComponent;
import java.lang.reflect.Type;
import java.util.Map;

import org.springframework.core.MethodParameter;
import org.springframework.http.HttpInputMessage;
import org.springframework.http.converter.HttpMessageConverter;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;
import org.springframework.web.servlet.mvc.method.annotation.RequestBodyAdviceAdapter;

import jakarta.servlet.http.HttpServletRequest;

import static com.plotline.backend.util.UsernameUtils.normalize;

/**
 * Checks top-level JSON body fields named in {@link ActingUser} (default "username", "userId")
 * against the signed-in user, for Map bodies, records and regular DTOs.
 */
@ControllerAdvice
public class OwnershipBodyAdvice extends RequestBodyAdviceAdapter {

    @Override
    public boolean supports(MethodParameter methodParameter, Type targetType,
                            Class<? extends HttpMessageConverter<?>> converterType) {
        return true;
    }

    @Override
    public Object afterBodyRead(Object body, HttpInputMessage inputMessage, MethodParameter parameter,
                                Type targetType, Class<? extends HttpMessageConverter<?>> converterType) {
        HttpServletRequest request = currentRequest();
        if (request == null || PublicEndpoints.isPublic(request)) {
            return body;
        }
        String me = CurrentUser.get(request);
        if (me == null) {
            throw new ForbiddenException("Please sign in again.");
        }

        ActingUser rule = OwnershipInterceptor.ruleFor(parameter.getMethod());
        if (!rule.checkBody()) {
            return body;
        }
        for (String name : rule.value()) {
            Object value = readProperty(body, name);
            if (value instanceof String s && !me.equals(normalize(s))) {
                throw new ForbiddenException();
            }
        }
        return body;
    }

    static Object readProperty(Object body, String name) {
        if (body == null) return null;
        if (body instanceof Map<?, ?> map) return map.get(name);
        try {
            Class<?> type = body.getClass();
            if (type.isRecord()) {
                for (RecordComponent component : type.getRecordComponents()) {
                    if (component.getName().equals(name)) return component.getAccessor().invoke(body);
                }
                return null;
            }
            String getter = "get" + Character.toUpperCase(name.charAt(0)) + name.substring(1);
            for (Method method : type.getMethods()) {
                if (method.getName().equals(getter) && method.getParameterCount() == 0) return method.invoke(body);
            }
        } catch (ReflectiveOperationException e) {
            throw new ForbiddenException();
        }
        return null;
    }

    private static HttpServletRequest currentRequest() {
        return RequestContextHolder.getRequestAttributes() instanceof ServletRequestAttributes attributes
                ? attributes.getRequest() : null;
    }
}
