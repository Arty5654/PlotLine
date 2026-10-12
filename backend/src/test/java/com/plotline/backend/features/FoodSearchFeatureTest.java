package com.plotline.backend.features;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.when;

/** Nutrition → Search: detailed generic foods first, brands labeled, portions included. */
class FoodSearchFeatureTest extends FeatureTestBase {

    private static String food(String fdcId, String description, double kcal, String extra) {
        return "{\"fdcId\": " + fdcId + ", \"description\": \"" + description + "\", " + extra
                + " \"foodNutrients\": ["
                + "{\"nutrientNumber\": \"208\", \"unitName\": \"KCAL\", \"value\": " + kcal + "},"
                + "{\"nutrientNumber\": \"203\", \"unitName\": \"G\", \"value\": 20},"
                + "{\"nutrientNumber\": \"205\", \"unitName\": \"G\", \"value\": 0},"
                + "{\"nutrientNumber\": \"204\", \"unitName\": \"G\", \"value\": 15}]}";
    }

    private JsonNode search(User me, String q) throws Exception {
        return ok(getAs(me, "/api/nutrition/foods").param("q", q)).get("foods");
    }

    private static List<String> names(JsonNode foods) {
        List<String> names = new ArrayList<>();
        for (JsonNode f : foods) names.add(f.get("name").asText());
        return names;
    }

    @Test
    @DisplayName("Generic foods come first, best matches on top; brands follow, labeled and de-shouted")
    void genericFirstThenBrands() throws Exception {
        when(externalDataClient.postJson(anyString(), argThat(body -> body != null && body.contains("Foundation"))))
                .thenReturn("{\"foods\": ["
                        + food("1", "Spanish rice with ground beef", 150, "") + ","
                        + food("2", "Beef, ground, 80% lean meat / 20% fat, raw", 254, "") + ","
                        + food("3", "Beef, ground, 80% lean meat / 20% fat, raw", 254, "") + "," // listed twice
                        + food("4", "Chicken, roasted", 190, "") + ","                               // not what was asked
                        + food("5", "Beef, ground, 90% lean meat / 10% fat, cooked", 217,
                                "\"foodMeasures\": [{\"disseminationText\": \"1 patty\", \"gramWeight\": 85},"
                                + "{\"disseminationText\": \"Quantity not specified\", \"gramWeight\": 100}],")
                        + "]}");
        when(externalDataClient.postJson(anyString(), argThat(body -> body != null && body.contains("Branded"))))
                .thenReturn("{\"foods\": ["
                        + food("9", "GROUND BEEF", 312, "\"brandOwner\": \"Wal-Mart Stores, Inc.\", \"brandName\": \"\","
                                + " \"servingSize\": 112, \"servingSizeUnit\": \"g\", \"householdServingFullText\": \"4 ONZ\",")
                        + "]}");
        User me = newUser();

        JsonNode foods = search(me, "ground beef");
        // (joined, with % spelled out: AssertJ's failure message can't print a "%")
        assertThat(String.join(" | ", names(foods)).replace("%", "pct")).isEqualTo(
                "Beef, ground, 80pct lean meat / 20pct fat, raw | Beef, ground, 90pct lean meat / 10pct fat, cooked"
                + " | Spanish rice with ground beef | Ground Beef");
        assertThat(foods.get(0).get("kind").asText()).isEqualTo("generic");
        assertThat(foods.get(0).get("per100g").get("calories").asDouble()).isEqualTo(254);
        assertThat(foods.get(1).get("portions").get(0).get("label").asText()).isEqualTo("1 patty");
        assertThat(foods.get(1).get("portions")).hasSize(1); // "Quantity not specified" isn't a real portion

        JsonNode brand = foods.get(3);
        assertThat(brand.get("kind").asText()).isEqualTo("branded");
        assertThat(brand.get("brand").asText()).isEqualTo("Wal-Mart Stores, Inc.");
        assertThat(brand.get("portions").get(0).get("label").asText()).isEqualTo("4 oz (112 g)");
        assertThat(brand.get("portions").get(0).get("grams").asDouble()).isEqualTo(112);
    }

    @Test
    @DisplayName("\"80/20\" is searched the way USDA writes it (a slash made USDA reject the search)")
    void leanRatioIsTranslated() throws Exception {
        when(externalDataClient.postJson(anyString(), contains("ground beef 80% lean"))).thenReturn("{\"foods\": []}");
        User me = newUser();
        assertThat(search(me, "ground beef 80/20")).isEmpty();
    }

    @Test
    @DisplayName("If USDA can't be reached it's an error, not an empty result")
    void outageIsAnError() throws Exception {
        when(externalDataClient.postJson(anyString(), anyString())).thenThrow(new IOException("down"));
        User me = newUser();
        call(getAs(me, "/api/nutrition/foods").param("q", "rice"), 502);
    }
}
