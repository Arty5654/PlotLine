package com.plotline.backend.security;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.DefaultParameterNameDiscoverer;
import org.springframework.core.annotation.AnnotatedElementUtils;
import org.springframework.core.type.filter.AnnotationTypeFilter;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.lang.reflect.Method;
import java.lang.reflect.Parameter;
import java.lang.reflect.RecordComponent;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Guard rail for future endpoints: every request field that looks like it names a user must be
 * classified on its endpoint, either as the signed-in user (checked automatically) or as
 * possibly someone else (the endpoint checks permission itself). See {@link ActingUser}.
 */
class EndpointSecurityGuardTest {

    private static final Pattern USER_LIKE = Pattern.compile(
            "(?i).*(user|owner|sender|receiver|recipient|member|friend|requester|addedby|creator).*");

    private final DefaultParameterNameDiscoverer parameterNames = new DefaultParameterNameDiscoverer();

    @Test
    @DisplayName("Every user-like request field on every endpoint is classified")
    void everyUserFieldIsClassified() throws Exception {
        List<String> problems = new ArrayList<>();
        int endpoints = 0;

        for (Class<?> controller : controllers()) {
            for (Method method : controller.getDeclaredMethods()) {
                if (!AnnotatedElementUtils.hasAnnotation(method, RequestMapping.class)) continue;
                endpoints++;

                ActingUser rule = OwnershipInterceptor.ruleFor(method);
                Set<String> classified = new HashSet<>(List.of(rule.value()));
                classified.addAll(List.of(rule.others()));

                for (String field : userLikeFields(method, rule.checkBody())) {
                    if (!classified.contains(field)) {
                        problems.add(controller.getSimpleName() + "." + method.getName() + " -> \"" + field + "\"");
                    }
                }
            }
        }

        assertThat(endpoints).as("endpoints scanned").isGreaterThan(100);
        assertThat(problems)
                .as("Unclassified user fields. Add them to @ActingUser(value = ...) if they must be the "
                        + "signed-in user, or to others = ... (and check permission in the endpoint) if not")
                .isEmpty();
    }

    @Test
    @DisplayName("Endpoints that let a field name someone else say so explicitly")
    void othersAreDeliberate() throws Exception {
        List<String> othersEndpoints = new ArrayList<>();
        for (Class<?> controller : controllers()) {
            for (Method method : controller.getDeclaredMethods()) {
                ActingUser rule = method.getAnnotation(ActingUser.class);
                if (rule != null && rule.others().length > 0) {
                    othersEndpoints.add(controller.getSimpleName() + "." + method.getName());
                }
            }
        }
        // a sanity check that the cross-user endpoints reviewed for this change are all annotated
        assertThat(othersEndpoints).contains(
                "FriendsController.createOrUpdateFriendRequest", "FriendsController.getFriendRequests",
                "FriendsController.removeFriend", "CalendarController.createEvent", "ChatController.addReaction",
                "ProfileController.getProfile", "CalendarAccessController.getSharedEvents",
                "GroceryListController.shareGroceryList");
    }

    private List<Class<?>> controllers() throws ClassNotFoundException {
        ClassPathScanningCandidateComponentProvider scanner = new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(new AnnotationTypeFilter(RestController.class));
        scanner.addIncludeFilter(new AnnotationTypeFilter(org.springframework.stereotype.Controller.class));
        List<Class<?>> classes = new ArrayList<>();
        for (BeanDefinition candidate : scanner.findCandidateComponents("com.plotline.backend")) {
            classes.add(Class.forName(candidate.getBeanClassName()));
        }
        return classes;
    }

    private Set<String> userLikeFields(Method method, boolean includeBody) {
        Set<String> fields = new HashSet<>();
        String[] names = parameterNames.getParameterNames(method);
        Parameter[] parameters = method.getParameters();

        for (int i = 0; i < parameters.length; i++) {
            Parameter parameter = parameters[i];
            String javaName = names != null ? names[i] : parameter.getName();

            PathVariable pathVariable = parameter.getAnnotation(PathVariable.class);
            RequestParam requestParam = parameter.getAnnotation(RequestParam.class);
            if (pathVariable != null) {
                addIfUserLike(fields, firstNonBlank(pathVariable.value(), pathVariable.name(), javaName));
            } else if (requestParam != null) {
                addIfUserLike(fields, firstNonBlank(requestParam.value(), requestParam.name(), javaName));
            } else if (parameter.getAnnotation(RequestBody.class) != null && includeBody) {
                Class<?> type = parameter.getType();
                if (Map.class.isAssignableFrom(type) || type == String.class) continue; // checked at runtime
                if (type.isRecord()) {
                    for (RecordComponent component : type.getRecordComponents()) {
                        if (component.getType() == String.class) addIfUserLike(fields, component.getName());
                    }
                } else {
                    for (Method getter : type.getMethods()) {
                        if (getter.getParameterCount() == 0 && getter.getReturnType() == String.class
                                && getter.getName().startsWith("get") && getter.getName().length() > 3) {
                            String property = Character.toLowerCase(getter.getName().charAt(3)) + getter.getName().substring(4);
                            addIfUserLike(fields, property);
                        }
                    }
                }
            }
        }
        return fields;
    }

    private static void addIfUserLike(Set<String> fields, String name) {
        if (name != null && USER_LIKE.matcher(name).matches()) fields.add(name);
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) return value;
        }
        return null;
    }
}
