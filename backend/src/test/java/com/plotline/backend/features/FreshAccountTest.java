package com.plotline.backend.features;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.core.DefaultParameterNameDiscoverer;
import org.springframework.core.MethodParameter;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ValueConstants;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.mvc.method.RequestMappingInfo;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * A brand-new account opens every screen before saving anything. Every GET endpoint must answer
 * 2xx (an empty result), not an error: the app shows an error banner for failures, so "nothing
 * saved yet" must never look like one. The only exception is a 404 the app is known to read as
 * "nothing yet" (NOT_FOUND_MEANS_EMPTY).
 *
 * Endpoints are found automatically, so new ones are covered without editing this test. Only
 * endpoints that need the id of something the user would have created first (a grocery list, a
 * meal) can't be called, and the test checks that list doesn't grow by accident.
 */
class FreshAccountTest extends FeatureTestBase {

    @Autowired
    @Qualifier("requestMappingHandlerMapping")
    private RequestMappingHandlerMapping mappings;

    private static final Pattern PATH_VARIABLE = Pattern.compile("\\{([^}:]+)(:[^}]*)?}");

    // example values for fields that aren't a username, as the app sends them
    private static final Map<String, List<String>> SAMPLES = Map.of(
            "type", List.of("weekly", "monthly"),
            "month", List.of("2026-10"),
            "week_start", List.of("2026-10-04"),
            "dateKey", List.of("2026-10-06"),
            "startDate", List.of("2026-10-01"),
            "endDate", List.of("2026-10-31"),
            "q", List.of("apple"),
            "risk", List.of("medium"));

    // these need the id of something the user creates first
    private static final Set<String> NEEDS_EXISTING_ITEM = Set.of(
            "/api/groceryLists/{listId}/details",
            "/api/groceryLists/{listId}/items",
            "/api/meals/{username}/meals/{mealID}");

    // these call an outside service, so they're tested with fakes elsewhere (and must not hit the real one here)
    private static final Set<String> OUTSIDE_SERVICE = Set.of(
            "/api/plaid/link_token",
            "/api/plaid/accounts",
            "/api/news",
            "/api/nutrition/food-search");

    // 404 means "nothing saved yet" here, and the app treats it that way (no error banner):
    // budgets show the default categories or the quiz, portfolio and food log show empty
    private static final Set<String> NOT_FOUND_MEANS_EMPTY = Set.of(
            "/api/budget/{username}/{type}",
            "/api/budget/{username}/{type}/groceries",
            "/api/budget/api/budget/{username}/{type}",
            "/api/llm/budget/edited/{username}/{type}",
            "/api/llm/portfolio/{username}",
            "/api/nutrition/{username}/{dateKey}",
            "/api/nutrition/{username}/user-data");

    @Test
    @DisplayName("A new account can open every screen without errors")
    void everyReadWorksBeforeAnythingIsSaved() throws Exception {
        User me = newUser();
        Map<String, Integer> failures = new TreeMap<>();
        List<String> notCalled = new ArrayList<>();
        int called = 0;

        for (Map.Entry<RequestMappingInfo, HandlerMethod> entry : mappings.getHandlerMethods().entrySet()) {
            if (!entry.getKey().getMethodsCondition().getMethods().contains(RequestMethod.GET)) continue;

            for (String pattern : entry.getKey().getPatternValues()) {
                if (OUTSIDE_SERVICE.contains(pattern)) continue;
                List<String> paths = fillPath(pattern, me.name());
                if (paths == null) { notCalled.add(pattern); continue; }

                for (String path : paths) {
                    MockHttpServletRequestBuilder request = as(me, get(path));
                    if (!addParams(request, entry.getValue(), me.name())) { notCalled.add(pattern); break; }
                    int status;
                    try {
                        status = mockMvc.perform(request).andReturn().getResponse().getStatus();
                    } catch (Exception e) {
                        status = 500; // an unhandled exception is a 500 on the real server
                    }
                    called++;
                    if (status == 404 && NOT_FOUND_MEANS_EMPTY.contains(pattern)) continue;
                    if (status >= 400) failures.put(path.replace(me.name(), "{me}"), status);
                }
            }
        }

        assertThat(called).as("endpoints called").isGreaterThan(40);
        assertThat(notCalled).as("endpoints this test can't call; add a sample value to SAMPLES")
                .containsExactlyInAnyOrderElementsOf(NEEDS_EXISTING_ITEM);
        assertThat(failures).as("screens that fail for a new account (status by endpoint)").isEmpty();
    }

    // every combination of sample values for the path's variables; null if one has no sample
    private static List<String> fillPath(String pattern, String username) {
        List<String> paths = new ArrayList<>(List.of(pattern));
        Matcher m = PATH_VARIABLE.matcher(pattern);
        while (m.find()) {
            String variable = m.group(0);
            List<String> values = isUserLike(m.group(1)) ? List.of(username) : SAMPLES.get(m.group(1));
            if (values == null) return null;
            List<String> next = new ArrayList<>();
            for (String path : paths) {
                for (String value : values) next.add(path.replace(variable, value));
            }
            paths = next;
        }
        return paths;
    }

    private static boolean addParams(MockHttpServletRequestBuilder request, HandlerMethod handler, String username) {
        for (MethodParameter parameter : handler.getMethodParameters()) {
            parameter.initParameterNameDiscovery(new DefaultParameterNameDiscoverer());
            RequestParam param = parameter.getParameterAnnotation(RequestParam.class);
            if (param == null) continue;
            String name = name(param, parameter);
            boolean required = param.required() && ValueConstants.DEFAULT_NONE.equals(param.defaultValue());
            if (isUserLike(name)) {
                request.param(name, username);
            } else if (SAMPLES.containsKey(name)) {
                request.param(name, SAMPLES.get(name).get(0));
            } else if (required) {
                return false;
            }
        }
        return true;
    }

    private static String name(RequestParam param, MethodParameter parameter) {
        if (!param.value().isBlank()) return param.value();
        if (!param.name().isBlank()) return param.name();
        return parameter.getParameterName();
    }

    private static boolean isUserLike(String name) {
        return name != null && name.toLowerCase().matches(".*(user|owner).*");
    }
}
