package com.plotline.backend.features;

import com.fasterxml.jackson.databind.JsonNode;
import com.plotline.backend.dto.DietaryRestrictions;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

/** Grocery page: lists made by AI from a meal (with their recipe) or from a goal. */
class GroceryFeatureTest extends FeatureTestBase {

    private static final String WITH_RECIPE = """
        {"items": [{"name": "Spaghetti", "quantity": 1}, {"name": "Ground Beef", "quantity": 1, "notes": "1 lb"}],
         "meal": {"mealName": "Spaghetti Bolognese", "ingredients": ["1 lb spaghetti", "1 lb ground beef"],
                  "recipe": ["Step 1: Brown the beef.", "Step 2: Simmer with sauce.", "Step 3: Serve over pasta."],
                  "optionalToppings": ["Parmesan"]}}
        """;

    private JsonNode details(User me, String listId) throws Exception {
        return ok(getAs(me, "/api/groceryLists/{id}/details", listId).param("username", me.name()));
    }

    @Test
    @DisplayName("From a meal: one AI answer makes the grocery list and its recipe, linked together")
    void fromMealMakesListAndRecipe() throws Exception {
        when(openAIService.generateGroceryListFromMeal(anyString(), any(DietaryRestrictions.class))).thenReturn(WITH_RECIPE);
        User me = newUser();

        String listId = ok(postJson(me, "/api/groceryLists/generate-from-meal",
                Map.of("mealName", "Spaghetti Bolognese", "username", me.name()))).asText();

        JsonNode list = details(me, listId);
        assertThat(list.get("source").asText()).isEqualTo("meal");
        assertThat(list.get("items")).hasSize(2);
        String mealId = list.get("mealID").asText();
        assertThat(mealId).isNotBlank();

        JsonNode meal = ok(getAs(me, "/api/meals/{u}/meals/{m}", me.name(), mealId));
        assertThat(meal.get("mealName").asText()).isEqualTo("Spaghetti Bolognese");
        assertThat(meal.get("recipe")).hasSize(3);
        assertThat(meal.get("listID").asText()).isEqualTo(listId);
    }

    @Test
    @DisplayName("From a meal: an answer without a recipe (the old format) still makes the list, with no recipe yet")
    void fromMealOldFormat() throws Exception {
        when(openAIService.generateGroceryListFromMeal(anyString(), any(DietaryRestrictions.class)))
                .thenReturn("[{\"name\": \"Eggs\", \"quantity\": 6}]");
        User me = newUser();

        String listId = ok(postJson(me, "/api/groceryLists/generate-from-meal",
                Map.of("mealName", "Omelette", "username", me.name()))).asText();

        JsonNode list = details(me, listId);
        assertThat(list.get("items")).hasSize(1);
        assertThat(list.get("source").asText()).isEqualTo("meal");
        assertThat(list.path("mealID").isMissingNode() || list.get("mealID").isNull()).isTrue();
    }

    @Test
    @DisplayName("From a meal with dietary changes: the list is marked modified and still gets its recipe")
    void fromMealModified() throws Exception {
        when(openAIService.generateGroceryListFromMeal(anyString(), any(DietaryRestrictions.class))).thenReturn(
                WITH_RECIPE.replaceFirst("\\{", "{\"modifications\": \"Used turkey instead of beef\", "));
        User me = newUser();

        String body = ok(postJson(me, "/api/groceryLists/generate-from-meal",
                Map.of("mealName", "Spaghetti Bolognese", "username", me.name()))).asText();
        assertThat(body).startsWith("MODIFIED:").contains("Used turkey instead of beef");
        String listId = objectMapper.readTree(body.substring("MODIFIED:".length())).get("listId").asText();

        JsonNode list = details(me, listId);
        assertThat(list.get("name").asText()).contains("Modified");
        assertThat(list.get("mealID").asText()).isNotBlank();
    }

    @Test
    @DisplayName("From a goal: the list is marked as a goal list")
    void fromGoal() throws Exception {
        when(openAIService.generateGroceryListFromGoal(anyString(), anyString()))
                .thenReturn("{\"title\": \"Eat more protein\", \"items\": [{\"name\": \"Chicken\", \"quantity\": 2}]}");
        User me = newUser();

        JsonNode response = ok(postJson(me, "/api/groceryLists/generate-list-from-goal",
                Map.of("goal", "Eat more protein", "username", me.name())));
        JsonNode list = details(me, response.get("listId").asText());
        assertThat(list.get("source").asText()).isEqualTo("goal");
    }

    @Test
    @DisplayName("Archiving keeps the list as it is now (checked items and all), and restoring brings it back the same")
    void archiveKeepsCheckmarks() throws Exception {
        User me = newUser();
        String listId = java.util.UUID.randomUUID().toString().toUpperCase();
        Map<String, Object> stale = Map.of("id", listId, "name", "Weekly shop", "username", me.name(), "items", java.util.List.of());
        ok(postJson(me, "/api/groceryLists/create-grocery-list", stale));

        String milk = java.util.UUID.randomUUID().toString().toUpperCase();
        String eggs = java.util.UUID.randomUUID().toString().toUpperCase();
        for (String[] item : new String[][]{{milk, "Milk"}, {eggs, "Eggs"}}) {
            ok(json(me, org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                    .post("/api/groceryLists/{id}/items", listId).param("username", me.name()),
                    Map.of("listId", listId, "id", item[0], "name", item[1], "quantity", 1, "checked", false)));
        }
        ok(as(me, org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                .patch("/api/groceryLists/{id}/items/{item}/toggle", listId, milk).param("username", me.name())));

        // half done, and the app sends its old copy (no items): the saved list is what gets archived,
        // along with what this trip added to grocery spending
        ok(json(me, org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                .post("/api/groceryLists/archive/{u}", me.name()).param("spentAmount", "12.5").param("spentDate", "2026-10-11"), stale));
        JsonNode archived = null;
        for (JsonNode l : ok(getAs(me, "/api/groceryLists/archived/{u}", me.name()))) {
            if (l.get("id").asText().equals(listId)) archived = l;
        }
        assertThat(archived).isNotNull();
        assertThat(checked(archived)).isEqualTo(Map.of("Milk", true, "Eggs", false));
        assertThat(archived.get("spentAmount").asDouble()).isEqualTo(12.5);
        assertThat(archived.get("spentDate").asText()).isEqualTo("2026-10-11");

        ok(postJson(me, "/api/groceryLists/restore/" + me.name(), stale));
        JsonNode restored = details(me, listId);
        assertThat(checked(restored)).isEqualTo(Map.of("Milk", true, "Eggs", false));
        assertThat(restored.get("spentAmount").isNull()).isTrue(); // the app already asked about it
    }

    private static Map<String, Boolean> checked(JsonNode list) {
        Map<String, Boolean> result = new java.util.HashMap<>();
        for (JsonNode item : list.get("items")) result.put(item.get("name").asText(), item.get("checked").asBoolean());
        return result;
    }
}