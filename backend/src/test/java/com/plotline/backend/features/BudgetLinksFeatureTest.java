package com.plotline.backend.features;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

import java.time.LocalDate;
import java.time.YearMonth;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.fasterxml.jackson.databind.JsonNode;

/** Everything on the Budget page stays linked: the budget, Monthly Costs' fixed costs, the Plan, the week. */
class BudgetLinksFeatureTest extends FeatureTestBase {

    private User withBudgetAndPlan() throws Exception {
        User me = newUser();
        Map<String, Object> budget = new LinkedHashMap<>();
        budget.put("Rent", 1250);
        budget.put("Groceries", 400);
        budget.put("Eating Out", 250);
        budget.put("Debt - Visa", 40);
        budget.put("Extra Debt Payment", 50);
        budget.put("Savings - Trip", 150);
        budget.put("Savings", 300);
        ok(postJson(me, "/api/llm/budget/save", Map.of("username", me.name(), "budget", budget, "answers", Map.of("monthlyNet", 3000))));
        Map<String, Object> visa = Map.of("id", "D1", "name", "Visa", "balance", 1500, "apr", 24, "minPayment", 40);
        Map<String, Object> trip = Map.of("id", "G1", "name", "Trip", "target", 3000, "saved", 300);
        ok(json(me, put("/api/plan/{u}", me.name()), Map.of("debts", List.of(visa), "savingsGoals", List.of(trip), "extraDebtPayment", 50)));
        return me;
    }

    private Map<String, Double> monthly(User me) throws Exception { return numbers(ok(getAs(me, "/api/budget/{u}/{t}", me.name(), "monthly")).get("budget")); }
    private Map<String, Double> weekly(User me) throws Exception { return numbers(ok(getAs(me, "/api/budget/{u}/{t}", me.name(), "weekly")).get("budget")); }

    private Map<String, Double> fixed(User me) throws Exception {
        Map<String, Double> out = new HashMap<>();
        ok(getAs(me, "/api/costs/fixed/{u}", me.name())).forEach(f -> out.put(f.get("category").asText(), f.get("amount").asDouble()));
        return out;
    }

    private static Map<String, Double> numbers(JsonNode n) {
        Map<String, Double> out = new LinkedHashMap<>();
        n.fields().forEachRemaining(e -> out.put(e.getKey(), e.getValue().asDouble()));
        return out;
    }

    @Test
    @DisplayName("The Monthly Budget editor: fixed costs follow, and so do the debt planner's minimum and extra payment")
    void editorUpdatesEverything() throws Exception {
        User me = withBudgetAndPlan();
        Map<String, Double> b = monthly(me);
        b.put("Rent", 1300.0);
        b.put("Debt - Visa", 55.0);
        b.put("Extra Debt Payment", 100.0);
        b.put("Savings - Trip", 200.0);
        ok(postJson(me, "/api/budget", Map.of("username", me.name(), "type", "monthly", "budget", b)));

        Map<String, Double> f = fixed(me);
        assertThat(f).containsEntry("Rent", 1300.0).containsEntry("Debt - Visa", 55.0)
                .containsEntry("Extra Debt Payment", 100.0).containsEntry("Savings - Trip", 200.0);
        JsonNode plan = ok(getAs(me, "/api/plan/{u}", me.name()));
        assertThat(plan.get("extraDebtPayment").asDouble()).isEqualTo(100.0);
        assertThat(plan.get("debts").get(0).get("minPayment").asDouble()).isEqualTo(55.0);
        assertThat(weekly(me).get("Rent")).isEqualTo(325.0);
    }

    @Test
    @DisplayName("Retune suggestions: fixed costs follow")
    void retuneUpdatesFixed() throws Exception {
        User me = withBudgetAndPlan();
        ok(postJson(me, "/api/budget/" + me.name() + "/retune/apply", Map.of("changes", Map.of("Savings", 250))));
        assertThat(fixed(me)).containsEntry("Savings", 250.0);
    }

    @Test
    @DisplayName("Revert: both copies go back to the quiz's budget, the Plan's lines and active cuts stay")
    void revertKeepsThePlan() throws Exception {
        User me = withBudgetAndPlan();
        // the Plan raised the Visa minimum; "Save for it" made a goal funded by an Eating Out cut
        JsonNode plan = ok(getAs(me, "/api/plan/{u}", me.name()));
        Map<String, Object> next = objectMapper.convertValue(plan, Map.class);
        next.put("debts", List.of(Map.of("id", "D1", "name", "Visa", "balance", 1500, "apr", 24, "minPayment", 60)));
        ok(json(me, put("/api/plan/{u}", me.name()), next));
        ok(postJson(me, "/api/afford/" + me.name() + "/save-for-it", Map.of("item", "Bike", "price", 2000, "cuts", List.of("Eating Out"))));
        // then they edited Rent and Groceries by hand
        Map<String, Double> b = monthly(me);
        b.put("Rent", 1400.0);
        b.put("Groceries", 500.0);
        ok(postJson(me, "/api/budget", Map.of("username", me.name(), "type", "monthly", "budget", b)));
        double bike = monthly(me).get("Savings - Bike");

        ok(postJson(me, "/api/llm/budget/revert/" + me.name() + "/monthly", Map.of()));
        Map<String, Double> m = monthly(me), w = weekly(me);
        assertThat(m).containsEntry("Rent", 1250.0).containsEntry("Groceries", 400.0)       // hand edits undone
                .containsEntry("Debt - Visa", 60.0)                                          // the planner's minimum
                .containsEntry("Savings - Bike", bike)                                       // the goal still saving
                .containsEntry("Eating Out", 165.0);                                         // its cut still made
        assertThat(w.get("Rent")).isEqualTo(312.5);                                          // the weekly copy too
        assertThat(fixed(me)).containsEntry("Rent", 1250.0).containsEntry("Debt - Visa", 60.0);
    }

    @Test
    @DisplayName("A day typed on Monthly Costs counts this week too (the grocery card)")
    void dailyEntryReachesTheWeek() throws Exception {
        User me = withBudgetAndPlan();
        String day = LocalDate.now().toString();
        ok(postJson(me, "/api/costs/merge-dated", Map.of("username", me.name(), "type", "monthly", "date", day,
                "costs", Map.of("Groceries", 40))));
        JsonNode week = ok(getAs(me, "/api/costs/{u}/{t}", me.name(), "weekly").param("date", day));
        assertThat(week.toString()).contains("Groceries");
        assertThat(week.path("costs").path("Groceries").asDouble(week.path("totals").path("Groceries").asDouble())).isEqualTo(40.0);
        // saving the same day again sets it (no double count)
        ok(postJson(me, "/api/costs/merge-dated", Map.of("username", me.name(), "type", "monthly", "date", day,
                "costs", Map.of("Groceries", 35))));
        week = ok(getAs(me, "/api/costs/{u}/{t}", me.name(), "weekly").param("date", day));
        assertThat(week.path("costs").path("Groceries").asDouble(week.path("totals").path("Groceries").asDouble())).isEqualTo(35.0);
    }

    @Test
    @DisplayName("Receipt items sorted by hand in an older app (POST /api/costs/merge) count as today's spending")
    void oldReceiptSortingCounts() throws Exception {
        User me = withBudgetAndPlan();
        ok(postJson(me, "/api/costs/merge", Map.of("username", me.name(), "type", "monthly", "costs", Map.of("Eating Out", 12))));
        JsonNode totals = ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", YearMonth.now().toString())).get("totals");
        assertThat(totals.get("Eating Out").asDouble()).isEqualTo(12.0);
    }
}
