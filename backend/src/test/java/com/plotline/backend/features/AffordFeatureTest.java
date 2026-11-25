package com.plotline.backend.features;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.fasterxml.jackson.databind.JsonNode;

/** Budget → Plan → "Can I afford it?": the check, "Save for it", and the cuts ending. */
class AffordFeatureTest extends FeatureTestBase {

    private User withBudget() throws Exception {
        User me = newUser();
        Map<String, Object> budget = new LinkedHashMap<>();
        budget.put("Rent", 1200);
        budget.put("Groceries", 400);
        budget.put("Eating Out", 300);
        budget.put("Entertainment", 100);
        budget.put("Savings", 200);
        // take-home $2,300: $100 a month isn't assigned
        ok(postJson(me, "/api/llm/budget/save", Map.of("username", me.name(), "budget", budget,
                "answers", Map.of("monthlyNet", 2300))));
        return me;
    }

    private JsonNode budget(User me) throws Exception {
        return ok(getAs(me, "/api/budget/{u}/{t}", me.name(), "monthly")).get("budget");
    }

    @Test
    @DisplayName("Check: fits from Savings and unassigned money; a laptop next month gets a cut plan")
    void check() throws Exception {
        User me = withBudget();
        JsonNode fits = ok(postJson(me, "/api/afford/{u}/check".replace("{u}", me.name()), Map.of("item", "Shoes", "price", 120)));
        assertThat(fits.get("verdict").asText()).isEqualTo("fits");

        JsonNode laptop = ok(postJson(me, "/api/afford/" + me.name() + "/check", Map.of("item", "Laptop", "price", 1500,
                "by", java.time.LocalDate.now().plusMonths(1).withDayOfMonth(28).toString())));
        assertThat(laptop.get("verdict").asText()).isIn("notYet", "delaysGoal");
        assertThat(laptop.get("cutPlan").get("cuts").get(0).get("line").asText()).isEqualTo("Eating Out");

        call(postJson(me, "/api/afford/" + me.name() + "/check", Map.of("price", 0)), 400);
        call(postJson(newUser(), "/api/afford/" + me.name() + "/check", Map.of("price", 10)), 403);
    }

    @Test
    @DisplayName("Save for it: a Plan goal funded by the cuts; reaching it gives the cuts back")
    void saveForItThenReach() throws Exception {
        User me = withBudget();
        JsonNode saved = ok(postJson(me, "/api/afford/" + me.name() + "/save-for-it", Map.of("item", "Laptop", "price", 1200,
                "cuts", List.of("Eating Out", "Entertainment"))));
        // cuts $105 + $35, then Savings $200, then $100 unassigned: $440 a month, 3 months
        assertThat(saved.get("monthly").asDouble()).isEqualTo(400.0);
        JsonNode budget = budget(me);
        assertThat(budget.get("Savings - Laptop").asDouble()).isEqualTo(400.0);
        assertThat(budget.get("Eating Out").asDouble()).isEqualTo(195.0);
        assertThat(budget.get("Entertainment").asDouble()).isEqualTo(65.0);
        assertThat(budget.has("Savings")).isFalse();                       // then all $200 of Savings, then $60 unassigned
        JsonNode plan = ok(getAs(me, "/api/plan/{u}", me.name()));
        JsonNode goal = plan.get("savingsGoals").get(0);
        assertThat(goal.get("name").asText()).isEqualTo("Laptop");
        assertThat(goal.get("cuts")).hasSize(2);

        // reached: Eating Out and Entertainment get their money back, the rest goes to Savings
        Map<String, Object> reached = objectMapper.convertValue(goal, Map.class);
        reached.put("saved", 1200);
        Map<String, Object> next = objectMapper.convertValue(plan, Map.class);
        next.put("savingsGoals", new ArrayList<>(List.of(reached)));
        ok(json(me, put("/api/plan/{u}", me.name()), next));
        budget = budget(me);
        assertThat(budget.get("Eating Out").asDouble()).isEqualTo(300.0);
        assertThat(budget.get("Entertainment").asDouble()).isEqualTo(100.0);
        assertThat(budget.has("Savings - Laptop")).isFalse();
        assertThat(budget.get("Savings").asDouble()).isEqualTo(260.0);
    }

    @Test
    @DisplayName("Deleting a Save-for-it goal also ends its cuts; a second goal with the same name gets a number")
    void deleteEndsCuts() throws Exception {
        User me = withBudget();
        ok(postJson(me, "/api/afford/" + me.name() + "/save-for-it", Map.of("item", "Bike", "price", 600,
                "cuts", List.of("Eating Out"))));
        JsonNode again = ok(postJson(me, "/api/afford/" + me.name() + "/save-for-it", Map.of("item", "Bike", "price", 100)));
        assertThat(again.get("goal").get("name").asText()).isEqualTo("Bike 2");

        JsonNode plan = ok(getAs(me, "/api/plan/{u}", me.name()));
        Map<String, Object> next = objectMapper.convertValue(plan, Map.class);
        next.put("savingsGoals", List.of(objectMapper.convertValue(plan.get("savingsGoals").get(1), Map.class)));
        ok(json(me, put("/api/plan/{u}", me.name()), next));
        assertThat(budget(me).get("Eating Out").asDouble()).isEqualTo(300.0);
    }

    @Test
    @DisplayName("Ongoing costs from the AI (cleaned up); I bought it logs today's spending and ends the goal's cuts")
    void ongoingAndBought() throws Exception {
        User me = withBudget();
        when(openAIService.estimateJson(anyString(), anyString())).thenReturn(
                "{\"costs\": [{\"name\": \"Insurance\", \"monthly\": 140.4}, {\"name\": \"Gas\", \"monthly\": 0}], \"note\": \"Typical for a used car.\"}");
        JsonNode ongoing = ok(postJson(me, "/api/afford/ongoing-costs", Map.of("item", "Used car", "price", 9000)));
        assertThat(ongoing.get("costs")).hasSize(1);
        assertThat(ongoing.get("costs").get(0).get("monthly").asDouble()).isEqualTo(140.0);
        call(postJson(me, "/api/afford/ongoing-costs", Map.of("item", "")), 400);

        JsonNode check = ok(postJson(me, "/api/afford/" + me.name() + "/check", Map.of("item", "Used car", "price", 120,
                "ongoingCosts", List.of(Map.of("name", "Insurance", "monthly", 140)))));
        assertThat(check.get("warnings").get(0).asText()).contains("$140 a month");

        // a wishlist item, saved for: the item points at the goal
        Map<String, Object> wish = Map.of("id", "W1", "item", "Laptop", "price", 1200, "addedOn", "2026-11-24", "remindOn", "2026-11-26");
        ok(json(me, put("/api/plan/{u}", me.name()), Map.of("wishlist", List.of(wish))));
        JsonNode saved = ok(postJson(me, "/api/afford/" + me.name() + "/save-for-it", Map.of("item", "Laptop", "price", 1200,
                "cuts", List.of("Eating Out"), "wishlistId", "W1")));
        String goalId = saved.get("goal").get("id").asText();
        JsonNode plan = ok(getAs(me, "/api/plan/{u}", me.name()));
        assertThat(plan.get("wishlist").get(0).get("goalId").asText()).isEqualTo(goalId);
        assertThat(budget(me).get("Eating Out").asDouble()).isEqualTo(195.0);

        // bought: $1,200 to Shopping... there's no Shopping line, so the first want line (Eating Out)
        JsonNode bought = ok(postJson(me, "/api/afford/" + me.name() + "/bought", Map.of("goalId", goalId, "wishlistId", "W1")));
        assertThat(bought.get("logged").asDouble()).isEqualTo(1200.0);
        assertThat(bought.get("category").asText()).isEqualTo("Eating Out");
        plan = ok(getAs(me, "/api/plan/{u}", me.name()));
        assertThat(plan.get("savingsGoals")).isEmpty();
        assertThat(plan.get("wishlist")).isEmpty();
        JsonNode budget = budget(me);
        assertThat(budget.get("Eating Out").asDouble()).isEqualTo(300.0);   // the cut ended
        assertThat(budget.has("Savings - Laptop")).isFalse();
        String month = java.time.YearMonth.now().toString();
        JsonNode costs = bytes("users/" + me.name().toLowerCase() + "/costs/monthly/" + month + ".json");
        assertThat(costs.get("totals").get("Eating Out").asDouble()).isEqualTo(1200.0);
        assertThat(costs.get("transactions").get(0).get("name").asText()).isEqualTo("Laptop");

        call(postJson(me, "/api/afford/" + me.name() + "/bought", Map.of("goalId", "nope")), 404);
        // a plain purchase in a category they pick
        assertThat(ok(postJson(me, "/api/afford/" + me.name() + "/bought", Map.of("item", "Shoes", "price", 80, "category", "Entertainment")))
                .get("category").asText()).isEqualTo("Entertainment");
    }

    @Test
    @DisplayName("Pausing the extra debt payment pauses it in the debt planner too; reaching the goal brings it back to both")
    void extraDebtFollowsThePlanner() throws Exception {
        User me = newUser();
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("Rent", 1200);
        b.put("Groceries", 400);
        b.put("Eating Out", 300);
        b.put("Debt - Visa", 40);
        b.put("Extra Debt Payment", 50);
        b.put("Savings", 200);
        ok(postJson(me, "/api/llm/budget/save", Map.of("username", me.name(), "budget", b, "answers", Map.of("monthlyNet", 2200))));
        Map<String, Object> visa = Map.of("id", "D1", "name", "Visa", "balance", 1500, "apr", 24, "minPayment", 40);
        ok(json(me, put("/api/plan/{u}", me.name()), Map.of("debts", List.of(visa), "extraDebtPayment", 50)));

        // $105 Eating Out + $50 extra debt + $200 Savings + $10 unassigned: $365 a month
        JsonNode saved = ok(postJson(me, "/api/afford/" + me.name() + "/save-for-it", Map.of("item", "Laptop", "price", 1000,
                "cuts", List.of("Eating Out", "Extra Debt Payment"))));
        assertThat(budget(me).has("Extra Debt Payment")).isFalse();
        JsonNode plan = ok(getAs(me, "/api/plan/{u}", me.name()));
        assertThat(plan.get("extraDebtPayment").asDouble()).isEqualTo(0.0);

        // reached (the app saves the plan as it has it): both come back, nothing counted twice
        Map<String, Object> next = objectMapper.convertValue(plan, Map.class);
        Map<String, Object> goal = objectMapper.convertValue(plan.get("savingsGoals").get(0), Map.class);
        goal.put("saved", 1000);
        next.put("savingsGoals", List.of(goal));
        JsonNode after = ok(json(me, put("/api/plan/{u}", me.name()), next));
        assertThat(after.get("extraDebtPayment").asDouble()).isEqualTo(50.0);
        JsonNode budget = budget(me);
        assertThat(budget.get("Extra Debt Payment").asDouble()).isEqualTo(50.0);
        assertThat(budget.get("Eating Out").asDouble()).isEqualTo(300.0);
        assertThat(budget.get("Savings").asDouble()).isEqualTo(200.0);     // all back to where it was
        assertThat(saved.get("monthly").asDouble()).isEqualTo(334.0);       // $1,000 over 3 months
        assertThat(ok(getAs(me, "/api/plan/{u}", me.name())).get("extraDebtPayment").asDouble()).isEqualTo(50.0);
    }

    @Test
    @DisplayName("A picked pause is made in full; only the picked subscription is paused, and it resumes when the goal ends")
    void pausesInFull() throws Exception {
        User me = newUser();
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("Rent", 1200);
        b.put("Groceries", 400);
        b.put("Eating Out", 300);
        b.put("Subscriptions", 30);
        b.put("Savings - Trip", 150);
        b.put("Savings", 200);
        ok(postJson(me, "/api/llm/budget/save", Map.of("username", me.name(), "budget", b, "answers", Map.of("monthlyNet", 2280))));
        ok(json(me, put("/api/plan/{u}", me.name()), Map.of("savingsGoals",
                List.of(Map.of("id", "G1", "name", "Trip", "target", 3000, "saved", 300)))));
        ok(postJson(me, "/api/subscriptions", Map.of("username", me.name(), "subscriptions", Map.of(
                "Netflix", Map.of("name", "Netflix", "cost", "17.99", "dueDate", "2026-12-06T12:00:00.000Z"),
                "Spotify", Map.of("name", "Spotify", "cost", "11.99", "dueDate", "2026-12-06T12:00:00.000Z")))));

        // a $300 pair of shoes: the Trip pause ($150) and Netflix ($18) are picked; both are made in full
        JsonNode saved = ok(postJson(me, "/api/afford/" + me.name() + "/save-for-it", Map.of("item", "Shoes", "price", 300,
                "cuts", List.of("Savings - Trip", "subscription:Netflix"))));
        assertThat(saved.get("pausedSubscriptions").toString()).contains("Netflix").doesNotContain("Spotify");
        JsonNode budget = budget(me);
        assertThat(budget.has("Savings - Trip")).isFalse();                  // paused, not lowered
        assertThat(budget.get("Subscriptions").asDouble()).isEqualTo(12.0);  // $30 − $18
        assertThat(saved.get("monthly").asDouble()).isGreaterThanOrEqualTo(168.0);
        JsonNode subs = ok(getAs(me, "/api/subscriptions/{u}", me.name())).get("subscriptions");
        assertThat(subs.get("Netflix").get("pausedForName").asText()).isEqualTo("Shoes");
        assertThat(subs.get("Spotify").has("pausedFor") && !subs.get("Spotify").get("pausedFor").isNull()).isFalse();

        // a paused subscription isn't offered again
        JsonNode check = ok(postJson(me, "/api/afford/" + me.name() + "/check", Map.of("item", "Bike", "price", 5000)));
        assertThat(check.get("cutPlan").toString()).doesNotContain("Pause Netflix").contains("Pause Spotify");

        // the goal deleted: the Trip and Netflix come back
        JsonNode plan = ok(getAs(me, "/api/plan/{u}", me.name()));
        Map<String, Object> next = objectMapper.convertValue(plan, Map.class);
        next.put("savingsGoals", List.of(objectMapper.convertValue(plan.get("savingsGoals").get(0), Map.class)));
        ok(json(me, put("/api/plan/{u}", me.name()), next));
        budget = budget(me);
        assertThat(budget.get("Savings - Trip").asDouble()).isEqualTo(150.0);
        assertThat(budget.get("Subscriptions").asDouble()).isEqualTo(30.0);
        subs = ok(getAs(me, "/api/subscriptions/{u}", me.name())).get("subscriptions");
        assertThat(subs.get("Netflix").path("pausedFor").isTextual()).isFalse();
    }
}
