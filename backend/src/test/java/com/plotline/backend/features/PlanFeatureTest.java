package com.plotline.backend.features;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.fasterxml.jackson.databind.JsonNode;

/** Budget → Plan: the saved plan, and the paycheck calculator. */
class PlanFeatureTest extends FeatureTestBase {

    @Test
    @DisplayName("A new account has an empty plan; a saved plan comes back; nobody else can read or change it")
    void plan() throws Exception {
        User me = newUser();
        User other = newUser();
        assertThat(ok(getAs(me, "/api/plan/{u}", me.name())).size()).isZero();

        Map<String, Object> plan = Map.of(
                "savingsGoals", List.of(Map.of("id", "g1", "name", "Japan trip", "target", 3000, "saved", 450)),
                "debts", List.of(Map.of("id", "d1", "name", "Student loan", "balance", 18000, "apr", 5.5, "minPayment", 200)),
                "emergencyFund", Map.of("months", 3, "saved", 1200));
        ok(json(me, put("/api/plan/{u}", me.name()), plan));
        JsonNode saved = ok(getAs(me, "/api/plan/{u}", me.name()));
        assertThat(saved.get("debts").get(0).get("apr").asDouble()).isEqualTo(5.5);
        assertThat(saved.get("savingsGoals").get(0).get("name").asText()).isEqualTo("Japan trip");

        call(getAs(other, "/api/plan/{u}", me.name()), 403);
        call(json(other, put("/api/plan/{u}", me.name()), Map.of()), 403);
    }

    @Test
    @DisplayName("Saving the plan keeps the budget's debt lines at the minimums, the extra payment and goal lines in step")
    void planUpdatesBudget() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/budget", Map.of("username", me.name(), "type", "monthly",
                "budget", Map.of("Rent", 1200, "Debt - Visa", 40, "Savings", 300, "Savings - Trip", 150))));
        Map<String, Object> trip = Map.of("id", "g1", "name", "Trip", "target", 3000, "saved", 0);
        Map<String, Object> visa = Map.of("id", "d1", "name", "Visa", "balance", 900, "apr", 24, "minPayment", 40);
        ok(json(me, put("/api/plan/{u}", me.name()), Map.of("debts", List.of(visa), "savingsGoals", List.of(trip))));

        // the planner: a new loan, a higher Visa minimum, $100 extra; the trip renamed
        Map<String, Object> visaMore = Map.of("id", "d1", "name", "Visa", "balance", 900, "apr", 24, "minPayment", 60);
        Map<String, Object> loan = Map.of("id", "d2", "name", "Car loan", "balance", 9000, "apr", 7, "minPayment", 250);
        Map<String, Object> japan = Map.of("id", "g1", "name", "Japan", "target", 3000, "saved", 0);
        ok(json(me, put("/api/plan/{u}", me.name()), Map.of("debts", List.of(visaMore, loan), "extraDebtPayment", 100,
                "savingsGoals", List.of(japan))));
        JsonNode budget = ok(getAs(me, "/api/budget/{u}/{t}", me.name(), "monthly")).get("budget");
        assertThat(budget.get("Debt - Visa").asDouble()).isEqualTo(60.0);
        assertThat(budget.get("Debt - Car loan").asDouble()).isEqualTo(250.0);
        assertThat(budget.get("Extra Debt Payment").asDouble()).isEqualTo(100.0);
        assertThat(budget.get("Savings - Japan").asDouble()).isEqualTo(150.0);
        assertThat(budget.has("Savings - Trip")).isFalse();
        assertThat(budget.get("Rent").asDouble()).isEqualTo(1200.0);
        // Monthly Costs counts the new debt line every month, like the quiz's
        assertThat(bytes("users/" + me.name().toLowerCase() + "/fixed_costs.json").toString()).contains("Debt - Car loan");

        // the goal deleted: its money goes back to Savings
        ok(json(me, put("/api/plan/{u}", me.name()), Map.of("debts", List.of(visaMore, loan), "extraDebtPayment", 100)));
        budget = ok(getAs(me, "/api/budget/{u}/{t}", me.name(), "monthly")).get("budget");
        assertThat(budget.has("Savings - Japan")).isFalse();
        assertThat(budget.get("Savings").asDouble()).isEqualTo(450.0);
    }

    @Test
    @DisplayName("Budget line for a goal or the emergency fund: from Savings, then unassigned money; less goes back to Savings")
    void budgetLine() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/budget", Map.of("username", me.name(), "type", "monthly",
                "budget", Map.of("Rent", 1200, "Savings", 300))));
        ok(json(me, put("/api/plan/{u}", me.name()), Map.of("savingsGoals",
                List.of(Map.of("id", "g1", "name", "Trip", "target", 3000, "saved", 0)))));

        JsonNode r = ok(postJson(me, "/api/plan/" + me.name() + "/budget-line", Map.of("line", "Savings - Trip", "amount", 200)));
        assertThat(r.get("budget").get("Savings - Trip").asDouble()).isEqualTo(200.0);
        assertThat(r.get("budget").get("Savings").asDouble()).isEqualTo(100.0);

        // more than Savings has, and no take-home known: nothing changes; says how high it can go
        JsonNode tooMuch = call(postJson(me, "/api/plan/" + me.name() + "/budget-line",
                Map.of("line", "Emergency Fund", "amount", 500)), 409);
        assertThat(tooMuch.get("available").asDouble()).isEqualTo(100.0);

        r = ok(postJson(me, "/api/plan/" + me.name() + "/budget-line", Map.of("line", "Savings - Trip", "amount", 50)));
        assertThat(r.get("budget").get("Savings").asDouble()).isEqualTo(250.0);

        // only the plan's own lines; only their own budget
        call(postJson(me, "/api/plan/" + me.name() + "/budget-line", Map.of("line", "Rent", "amount", 10)), 400);
        call(postJson(me, "/api/plan/" + me.name() + "/budget-line", Map.of("line", "Savings - Boat", "amount", 10)), 400);
        call(postJson(newUser(), "/api/plan/" + me.name() + "/budget-line", Map.of("line", "Emergency Fund", "amount", 10)), 403);
    }

    @Test
    @DisplayName("Paycheck calculator: 2026 take-home per paycheck, and every state is offered")
    void takeHome() throws Exception {
        User me = newUser();
        JsonNode r = ok(postJson(me, "/api/tools/take-home",
                Map.of("salary", 60000, "state", "TX", "k401Percent", 0, "preTaxHealth", 0, "payPeriods", 26)));
        assertThat(r.get("year").asInt()).isEqualTo(2026);
        assertThat(r.get("yearly").get("federalTax").asDouble()).isEqualTo(5020.0);
        assertThat(r.get("perPaycheck").get("takeHome").asDouble()).isEqualTo(Math.round((60000 - 5020 - 3720 - 870) / 26.0 * 100) / 100.0);

        call(postJson(me, "/api/tools/take-home", Map.of("salary", 60000, "payPeriods", 7)), 400);
        assertThat(ok(getAs(me, "/api/tools/states")).size()).isEqualTo(51);
    }
}
