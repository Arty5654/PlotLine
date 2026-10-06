package com.plotline.backend.features;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

/** Nutrition page: daily food log, goals/favorites, food photo analysis, meals, dietary restrictions. */
class NutritionFeatureTest extends FeatureTestBase {

    @Test
    @DisplayName("Daily food log: save a day and read it back; a day with nothing logged is 404 (the app treats that as empty)")
    void foodLog() throws Exception {
        User me = newUser();
        String entry = "{\"date\":\"2026-10-05\",\"foods\":[{\"id\":\"f1\",\"name\":\"Oatmeal\",\"calories\":300,"
                + "\"protein\":10,\"carbs\":54,\"fat\":6,\"mealType\":\"breakfast\"}]}";
        ok(as(me, put("/api/nutrition/{u}/{d}", me.name(), "2026-10-05")).contentType("application/json").content(entry));

        assertThat(ok(getAs(me, "/api/nutrition/{u}/{d}", me.name(), "2026-10-05")).toString()).contains("Oatmeal");
        call(getAs(me, "/api/nutrition/{u}/{d}", me.name(), "2026-10-06"), 404);
    }

    @Test
    @DisplayName("Calorie goal, favorites and saved meals are kept")
    void userData() throws Exception {
        User me = newUser();
        String data = "{\"favorites\":[{\"name\":\"Greek yogurt\"}],\"savedMeals\":[],\"goals\":{\"calorieGoal\":2200}}";
        ok(as(me, put("/api/nutrition/{u}/user-data", me.name())).contentType("application/json").content(data));

        String saved = ok(getAs(me, "/api/nutrition/{u}/user-data", me.name())).toString();
        assertThat(saved).contains("Greek yogurt").contains("2200");
    }

    @Test
    @DisplayName("Food photo analysis returns what the AI found")
    void analyzeFoodPhoto() throws Exception {
        when(openAIService.analyzeFoodFromImage(anyString()))
                .thenReturn("[{\"name\":\"Banana\",\"calories\":105,\"protein\":1,\"carbs\":27,\"fat\":0}]");
        User me = newUser();
        MockMultipartFile photo = new MockMultipartFile("image", "lunch.jpg", "image/jpeg", new byte[]{1, 2, 3});

        JsonNode result = ok(as(me, multipart("/api/nutrition/analyze-food").file(photo).param("username", me.name())));
        assertThat(result.toString()).contains("Banana");
    }

    @Test
    @DisplayName("Dietary restrictions: save and read back")
    void dietaryRestrictions() throws Exception {
        User me = newUser();
        ok(putJson(me, "/api/dietary-restrictions/update-dietary-restrictions/" + me.name(),
                Map.of("username", me.name(), "vegetarian", true, "nutFree", true)));

        JsonNode saved = ok(getAs(me, "/api/dietary-restrictions/get-dietary-restrictions/{u}", me.name()));
        assertThat(saved.get("vegetarian").asBoolean()).isTrue();
        assertThat(saved.get("nutFree").asBoolean()).isTrue();
        assertThat(saved.get("vegan").asBoolean()).isFalse();
    }

    @Test
    @DisplayName("Meals list starts empty")
    void meals() throws Exception {
        User me = newUser();
        assertThat(ok(getAs(me, "/api/meals/{u}/all", me.name()))).isEmpty();
    }

    @Test
    @DisplayName("Another user's food log is off limits")
    void ownDataOnly() throws Exception {
        User me = newUser();
        User other = newUser();
        call(getAs(me, "/api/nutrition/{u}/{d}", other.name(), "2026-10-05"), 403);
    }
}
