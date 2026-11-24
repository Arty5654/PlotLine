package com.plotline.backend.plan;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/** Plan changes reaching the budget's debt and goal lines. */
class PlanBudgetSyncTest {

    private final ObjectMapper json = new ObjectMapper();
    private static final LocalDate TODAY = LocalDate.of(2026, 11, 16);

    private JsonNode plan(List<Map<String, Object>> debts, double extra, List<Map<String, Object>> goals) {
        return json.valueToTree(Map.of("debts", debts, "extraDebtPayment", extra, "savingsGoals", goals));
    }

    private Map<String, Object> debt(String id, String name, double min) {
        return Map.of("id", id, "name", name, "balance", 1000, "apr", 20, "minPayment", min);
    }

    private Map<String, Double> budget() {
        Map<String, Double> b = new LinkedHashMap<>();
        b.put("Rent", 1200.0);
        b.put("Debt - Visa", 40.0);
        b.put("Savings", 300.0);
        b.put("Savings - Trip", 150.0);
        return b;
    }

    @Test
    @DisplayName("Debts: a new one is added at its minimum, a renamed one keeps its place, a deleted one goes")
    void debts() {
        JsonNode before = plan(List.of(debt("v", "Visa", 40), debt("s", "Student loan", 200)), 0, List.of());
        Map<String, Double> b = budget();
        b.put("Debt - Student loan", 200.0);
        JsonNode after = plan(List.of(debt("v", "Visa card", 55), debt("c", "Car loan", 310.4)), 0, List.of());
        assertThat(PlanBudgetSync.applyTo(b, before, after, TODAY)).isTrue();
        assertThat(b).containsEntry("Debt - Visa card", 55.0).containsEntry("Debt - Car loan", 310.0)
                .doesNotContainKeys("Debt - Visa", "Debt - Student loan");
        assertThat(List.copyOf(b.keySet()).indexOf("Debt - Visa card")).isEqualTo(1); // where Visa was
    }

    @Test
    @DisplayName("A loan that starts in two months has no line yet; once it's close, it gets one")
    void startsLater() {
        Map<String, Object> later = new LinkedHashMap<>(debt("s", "Student loan", 200));
        later.put("dueDate", TODAY.plusMonths(2).toString());
        Map<String, Double> b = budget();
        PlanBudgetSync.applyTo(b, plan(List.of(), 0, List.of()), plan(List.of(later), 0, List.of()), TODAY);
        assertThat(b).doesNotContainKey("Debt - Student loan");

        Map<String, Object> soon = new LinkedHashMap<>(later);
        soon.put("dueDate", TODAY.plusDays(20).toString());
        PlanBudgetSync.applyTo(b, plan(List.of(later), 0, List.of()), plan(List.of(soon), 0, List.of()), TODAY);
        assertThat(b).containsEntry("Debt - Student loan", 200.0);
    }

    @Test
    @DisplayName("Extra payment is its own line; goals: renamed with their line, deleted ones go back to Savings")
    void extraAndGoals() {
        Map<String, Object> trip = Map.of("id", "g1", "name", "Trip", "target", 3000, "saved", 0);
        Map<String, Object> japan = Map.of("id", "g1", "name", "Japan trip", "target", 3000, "saved", 0);
        Map<String, Double> b = budget();
        PlanBudgetSync.applyTo(b, plan(List.of(), 0, List.of(trip)), plan(List.of(), 120, List.of(japan)), TODAY);
        assertThat(b).containsEntry("Extra Debt Payment", 120.0).containsEntry("Savings - Japan trip", 150.0)
                .doesNotContainKey("Savings - Trip");

        PlanBudgetSync.applyTo(b, plan(List.of(), 120, List.of(japan)), plan(List.of(), 0, List.of()), TODAY);
        assertThat(b).doesNotContainKeys("Extra Debt Payment", "Savings - Japan trip").containsEntry("Savings", 450.0);
    }

    @Test
    @DisplayName("Saving the plan with no debt or goal changes (money added to a goal) leaves the budget alone")
    void unrelated() {
        Map<String, Object> trip = Map.of("id", "g1", "name", "Trip", "target", 3000, "saved", 0);
        Map<String, Object> more = Map.of("id", "g1", "name", "Trip", "target", 3000, "saved", 500);
        Map<String, Double> b = budget();
        b.put("Debt - Visa", 75.0); // more than the minimum, set on the budget page
        JsonNode before = plan(List.of(debt("v", "Visa", 40)), 0, List.of(trip));
        JsonNode after = plan(List.of(debt("v", "Visa", 40)), 0, List.of(more));
        assertThat(PlanBudgetSync.applyTo(b, before, after, TODAY)).isFalse();
        assertThat(b.get("Debt - Visa")).isEqualTo(75.0);
    }
}
