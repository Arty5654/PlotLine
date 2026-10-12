package com.plotline.backend.features;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;

import java.io.IOException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;

/** Nutrition → photo of a meal: foods with USDA numbers scaled to the estimated weight. */
class FoodPhotoFeatureTest extends FeatureTestBase {

    private static String usdaFood(String description, double kcal, double protein, double carbs, double fat) {
        return """
            {"description": "%s", "dataType": "SR Legacy", "foodNutrients": [
              {"nutrientNumber": "208", "unitName": "KCAL", "value": %s},
              {"nutrientNumber": "203", "unitName": "G", "value": %s},
              {"nutrientNumber": "205", "unitName": "G", "value": %s},
              {"nutrientNumber": "204", "unitName": "G", "value": %s}]}
            """.formatted(description, kcal, protein, carbs, fat);
    }

    // USDA's real top three for this search: the first is chicken skin, which is wrong
    private static final String CHICKEN_SEARCH = "{\"foods\": ["
            + usdaFood("Chicken, skin (drumsticks and thighs), cooked, roasted", 462, 16.6, 0, 44) + ","
            + usdaFood("Chicken, broilers or fryers, thigh, meat and skin, cooked, roasted", 232, 23.3, 0, 14.7) + ","
            + usdaFood("Chicken, broilers or fryers, thigh, meat only, cooked, roasted", 179, 24.8, 0, 8.15)
            + "]}";

    private JsonNode analyze(User me, String note, int status) throws Exception {
        MockMultipartFile image = new MockMultipartFile("image", "food.jpg", "image/jpeg", new byte[]{1, 2, 3});
        var request = multipart("/api/nutrition/analyze-food").file(image).param("username", me.name());
        if (note != null) request.param("note", note);
        return call(as(me, request), status);
    }

    @Test
    @DisplayName("Numbers come from the right USDA entry, scaled to the estimated weight; the note reaches the AI")
    void usdaScaledToPortion() throws Exception {
        when(openAIService.analyzeFoodFromImage(anyString(), eq("skinless, roasted"))).thenReturn("""
            {"items": [{"name": "Roasted chicken thigh", "usdaQuery": "chicken thigh meat only roasted",
                        "grams": 150, "portion": "1 large thigh", "calories": 270, "protein": 36, "carbs": 0, "fat": 13}]}
            """);
        when(externalDataClient.postJson(anyString(), contains("chicken thigh meat only roasted"))).thenReturn(CHICKEN_SEARCH);
        User me = newUser();

        JsonNode foods = analyze(me, "skinless, roasted", 200);
        assertThat(foods).hasSize(1);
        JsonNode thigh = foods.get(0);
        assertThat(thigh.get("id").asText()).isNotBlank();
        assertThat(thigh.get("source").asText()).isEqualTo("photo");
        assertThat(thigh.get("basis").asText()).isEqualTo("usda");
        assertThat(thigh.get("usdaName").asText()).contains("meat only"); // not the skin, which USDA ranked first
        assertThat(thigh.get("grams").asDouble()).isEqualTo(150);
        assertThat(thigh.get("servingSize").asText()).isEqualTo("150 g (1 large thigh)");
        assertThat(thigh.get("calories").asDouble()).isEqualTo(269);   // 179 kcal/100 g x 1.5
        assertThat(thigh.get("protein").asDouble()).isEqualTo(37.2);
        assertThat(thigh.get("fat").asDouble()).isEqualTo(12.2);
    }

    @Test
    @DisplayName("No good USDA match (or USDA down): the AI's own estimate is used")
    void fallsBackToEstimate() throws Exception {
        when(openAIService.analyzeFoodFromImage(anyString(), any())).thenReturn("""
            {"items": [{"name": "Mystery curry", "usdaQuery": "vegetable curry", "grams": 300, "portion": "1 bowl",
                        "calories": 420, "protein": 12, "carbs": 48, "fat": 20},
                       {"name": "Naan", "usdaQuery": "naan bread", "grams": 90, "portion": "1 piece",
                        "calories": 260, "protein": 8, "carbs": 45, "fat": 5}]}
            """);
        // a "match" with very different calories is the wrong food
        when(externalDataClient.postJson(anyString(), contains("vegetable curry"))).thenReturn("{\"foods\": ["
                + usdaFood("Vegetable oil, curry flavored", 884, 0, 0, 100) + "]}");
        when(externalDataClient.postJson(anyString(), contains("naan bread"))).thenThrow(new IOException("USDA is down"));
        User me = newUser();

        JsonNode foods = analyze(me, null, 200);
        assertThat(foods).hasSize(2);
        for (JsonNode food : foods) assertThat(food.get("basis").asText()).isEqualTo("estimate");
        assertThat(foods.get(0).get("calories").asDouble()).isEqualTo(420);
        assertThat(foods.get(1).get("carbs").asDouble()).isEqualTo(45);
    }

    @Test
    @DisplayName("Nothing recognizable is an empty list; a failed analysis is an error, not an empty list")
    void emptyAndFailure() throws Exception {
        User me = newUser();
        when(openAIService.analyzeFoodFromImage(anyString(), any())).thenReturn("{\"items\": []}");
        assertThat(analyze(me, null, 200)).isEmpty();

        when(openAIService.analyzeFoodFromImage(anyString(), any())).thenThrow(new IOException("OpenAI answered 500"));
        assertThat(analyze(me, null, 502).get("error").asText()).contains("Couldn't analyze");
    }
}
