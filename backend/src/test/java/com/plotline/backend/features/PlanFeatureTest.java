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
