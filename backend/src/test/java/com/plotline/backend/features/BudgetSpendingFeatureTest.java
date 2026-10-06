package com.plotline.backend.features;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/** Budget & spending pages: budgets, logged costs, fixed costs, spending periods, subscriptions. */
class BudgetSpendingFeatureTest extends FeatureTestBase {

    private JsonNode budget(User user, String type) throws Exception {
        return ok(getAs(user, "/api/budget/{u}/{t}", user.name(), type)).get("budget");
    }

    @Test
    @DisplayName("Saving a monthly budget also saves the matching weekly budget (÷4)")
    void monthlyBudgetScalesToWeekly() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/budget", Map.of("username", me.name(), "type", "monthly",
                "budget", Map.of("Rent", 1200.0, "Food", 400.0))));

        assertThat(budget(me, "monthly").get("Rent").asDouble()).isEqualTo(1200.0);
        assertThat(budget(me, "weekly").get("Rent").asDouble()).isEqualTo(300.0);
        assertThat(budget(me, "weekly").get("Food").asDouble()).isEqualTo(100.0);
    }

    @Test
    @Disabled("Known bug: BUGS.md #1 (uploads cut off accents/emoji)")
    @DisplayName("Budget categories with accents or emoji survive saving")
    void nonAsciiCategories() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/budget", Map.of("username", me.name(), "type", "monthly",
                "budget", Map.of("Café ☕", 60.0, "🍕 Food", 300.0))));

        JsonNode saved = budget(me, "monthly");
        assertThat(saved.get("Café ☕").asDouble()).isEqualTo(60.0);
        assertThat(saved.get("🍕 Food").asDouble()).isEqualTo(300.0);
    }

    @Test
    @DisplayName("Invalid budget type or missing budget is rejected")
    void budgetValidation() throws Exception {
        User me = newUser();
        call(postJson(me, "/api/budget", Map.of("username", me.name(), "type", "yearly", "budget", Map.of("Rent", 1.0))), 400);
        Map<String, Object> noBudget = new LinkedHashMap<>();
        noBudget.put("username", me.name());
        noBudget.put("type", "monthly");
        call(postJson(me, "/api/budget", noBudget), 400);
    }

    @Test
    @DisplayName("AI budget generation turns the quiz answers into a saved budget")
    void aiBudgetFromQuiz() throws Exception {
        when(openAIService.generateBudget(anyString()))
                .thenReturn("{\"Rent\": 1000, \"Groceries\": 350, \"Savings\": 300}");
        when(openAIService.generateResponseLocalTaxes(anyString())).thenReturn("0.05");
        User me = newUser();

        Map<String, Object> quiz = new LinkedHashMap<>();
        quiz.put("username", me.name());   // same keys BudgetQuizView sends
        quiz.put("yearlyIncome", 60000);
        quiz.put("401(k) Contribution", 5);
        quiz.put("primaryGoal", "Build savings");
        quiz.put("savingsPriority", "Medium");
        quiz.put("housingSituation", "Renting");
        quiz.put("carOwnership", "No car");
        quiz.put("eatingOutFrequency", "Sometimes");
        quiz.put("useDeviceLocation", false);
        quiz.put("hasDebt", false);
        quiz.put("city", "Cleveland");
        quiz.put("state", "Ohio");
        quiz.put("dependents", 0);
        quiz.put("spendingStyle", "Medium");
        quiz.put("debts", Map.of());
        quiz.put("knownCosts", Map.of());
        quiz.put("categories", List.of("Rent", "Groceries", "Savings"));
        JsonNode generated = ok(postJson(me, "/api/llm/budget", quiz));

        assertThat(generated.toString()).contains("Rent");
        assertThat(budget(me, "monthly").has("Rent")).isTrue();
    }

    @Test
    @DisplayName("Logging dated costs adds up by day and by month")
    void datedCostsAddUp() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/costs/add-dated", Map.of("username", me.name(), "type", "monthly",
                "date", "2026-10-03", "costs", Map.of("Food", 12.5))));
        ok(postJson(me, "/api/costs/add-dated", Map.of("username", me.name(), "type", "monthly",
                "date", "2026-10-03", "costs", Map.of("Food", 7.5, "Gas", 30))));
        ok(postJson(me, "/api/costs/add-dated", Map.of("username", me.name(), "type", "monthly",
                "date", "2026-10-15", "costs", Map.of("Food", 10))));

        JsonNode month = ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", "2026-10"));
        assertThat(month.get("days").get("2026-10-03").get("Food").asDouble()).isEqualTo(20.0);
        assertThat(month.get("totals").get("Food").asDouble()).isEqualTo(30.0);
        assertThat(month.get("totals").get("Gas").asDouble()).isEqualTo(30.0);
    }

    @Test
    @DisplayName("Fixed costs (rent, phone bill) are listed and counted in the month's totals until deleted")
    void fixedCosts() throws Exception {
        User me = newUser();
        JsonNode fixed = ok(postJson(me, "/api/costs/fixed/" + me.name(), Map.of("category", "Rent", "amount", 950)));
        assertThat(fixed.toString()).contains("Rent");
        String id = fixed.get(0).get("id").asText();

        JsonNode month = ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", "2026-10"));
        assertThat(month.get("totals").get("Rent").asDouble()).isEqualTo(950.0);
        assertThat(month.get("fixedCosts")).hasSize(1);

        ok(deleteAs(me, "/api/costs/fixed/{u}/{id}", me.name(), id));
        assertThat(ok(getAs(me, "/api/costs/fixed/{u}", me.name()))).isEmpty();
    }

    @Test
    @DisplayName("Spending for a date range: save, read back, clear")
    void spendingRange() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/spending", Map.of("username", me.name(), "startDate", "2026-10-01",
                "endDate", "2026-10-07", "spending", Map.of("Food", 55.0))));

        JsonNode saved = ok(getAs(me, "/api/spending/{u}/{s}/{e}", me.name(), "2026-10-01", "2026-10-07"));
        assertThat(saved.toString()).contains("55");

        ok(deleteAs(me, "/api/spending/{u}/{s}/{e}", me.name(), "2026-10-01", "2026-10-07"));
    }

    @Test
    @DisplayName("Subscriptions: save, list, delete one")
    void subscriptions() throws Exception {
        User me = newUser();
        Map<String, Object> netflix = Map.of("name", "Netflix", "cost", "15.49", "dueDate", "2026-10-20T00:00:00.000Z");
        Map<String, Object> spotify = Map.of("name", "Spotify", "cost", "11.99", "dueDate", "2026-10-05T00:00:00.000Z");
        ok(postJson(me, "/api/subscriptions", Map.of("username", me.name(),
                "subscriptions", Map.of("Netflix", netflix, "Spotify", spotify))));

        JsonNode listed = ok(getAs(me, "/api/subscriptions/{u}", me.name()));
        assertThat(listed.toString()).contains("Netflix", "Spotify");

        ok(deleteAs(me, "/api/subscriptions/{u}/{name}", me.name(), "Netflix"));
        assertThat(ok(getAs(me, "/api/subscriptions/{u}", me.name())).toString()).doesNotContain("Netflix").contains("Spotify");
    }

    @Test
    @DisplayName("Recurring charge detection spots a monthly subscription; snoozing hides it")
    void recurringCharges() throws Exception {
        User me = newUser();
        List<Map<String, Object>> charges = List.of(
                Map.of("name", "Netflix", "amount", 15.49, "date", "2026-07-12"),
                Map.of("name", "Netflix", "amount", 15.49, "date", "2026-08-12"),
                Map.of("name", "Netflix", "amount", 15.49, "date", "2026-09-12"),
                Map.of("name", "Corner Store", "amount", 4.20, "date", "2026-09-02"));
        JsonNode result = ok(postJson(me, "/api/subscriptions/recurring/analyze",
                Map.of("username", me.name(), "remindAfterMonths", 2, "charges", charges)));

        JsonNode prompts = result.get("prompts");
        assertThat(prompts.toString()).contains("Netflix").doesNotContain("Corner Store");
        String snoozeKey = prompts.get(0).get("snoozeKey").asText();

        ok(postJson(me, "/api/subscriptions/recurring/snooze",
                Map.of("username", me.name(), "snoozeKey", snoozeKey, "months", 2)));
        JsonNode after = ok(postJson(me, "/api/subscriptions/recurring/analyze",
                Map.of("username", me.name(), "remindAfterMonths", 2, "charges", charges)));
        assertThat(after.get("prompts").toString()).doesNotContain("Netflix");
    }

    @Test
    @DisplayName("Another user's budget and spending are off limits")
    void ownDataOnly() throws Exception {
        User me = newUser();
        User other = newUser();
        call(getAs(me, "/api/budget/{u}/{t}", other.name(), "monthly"), 403);
        call(getAs(me, "/api/costs/monthly/{u}", other.name()).param("month", "2026-10"), 403);
        call(postJson(me, "/api/costs/add-dated", Map.of("username", other.name(), "type", "monthly",
                "date", "2026-10-03", "costs", Map.of("Food", 1))), 403);
    }

    @Test
    @DisplayName("Receipt scan: the AI's categories are logged as that day's costs")
    void receiptScan() throws Exception {
        when(openAIService.analyzeReceiptFromImage(anyString()))
                .thenReturn("```json\n{\"Groceries\": 23.40, \"Household\": 6.10}\n```");
        User me = newUser();
        org.springframework.mock.web.MockMultipartFile photo =
                new org.springframework.mock.web.MockMultipartFile("image", "receipt.jpg", "image/jpeg", new byte[]{1, 2, 3});

        JsonNode result = ok(as(me, org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                .multipart("/api/costs/upload-receipt").file(photo).param("username", me.name()).param("date", "2026-10-04")));
        assertThat(result.get("_addedCosts").get("Groceries").asDouble()).isEqualTo(23.40);

        JsonNode month = ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", "2026-10"));
        assertThat(month.get("days").get("2026-10-04").get("Groceries").asDouble()).isEqualTo(23.40);
        assertThat(month.get("totals").get("Household").asDouble()).isEqualTo(6.10);
    }

    @Test
    @DisplayName("Linked banks: with no bank connected the account list is empty")
    void noLinkedBanks() throws Exception {
        User me = newUser();
        assertThat(ok(getAs(me, "/api/plaid/accounts").param("username", me.name()))).isEmpty();
    }
}

