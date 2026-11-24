package com.plotline.backend.features;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.YearMonth;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;

import com.fasterxml.jackson.databind.JsonNode;
import com.plotline.backend.plaid.TokenStore;

/** The budget quiz's new questions, commute prices, and tuning the budget from real spending. */
class QuizAndRetuneFeatureTest extends FeatureTestBase {

    @Autowired TokenStore tokenStore;

    private Map<String, Object> quiz(User me) {
        Map<String, Object> quiz = new LinkedHashMap<>();
        quiz.put("username", me.name());
        quiz.put("yearlyIncome", 60000);
        quiz.put("401(k) Contribution", 0);
        quiz.put("city", "Richmond");
        quiz.put("state", "VA");
        quiz.put("dependents", 0);
        quiz.put("spendingStyle", "Medium");
        quiz.put("housingSituation", "Renting");
        quiz.put("carOwnership", "One Car");
        quiz.put("eatingOutFrequency", "Sometimes");
        quiz.put("categories", List.of("Rent", "Groceries", "Utilities", "Health Insurance", "Transportation", "Savings"));
        quiz.put("knownCosts", Map.of());
        return quiz;
    }

    @Test
    @DisplayName("Quiz: rent share, commute and insurance reach the AI; insurance raises take-home; a loan that starts later isn't budgeted; minimums are used")
    void quizDetails() throws Exception {
        when(openAIService.generateBudget(anyString())).thenReturn("{\"Rent\": 800, \"Groceries\": 350, \"Savings\": 300}");
        when(openAIService.generateResponseLocalTaxes(anyString())).thenReturn("0");
        User me = newUser();

        Map<String, Object> plain = quiz(me);
        ok(postJson(me, "/api/llm/budget", plain));
        double netWithoutInsurance = ok(getAs(me, "/api/llm/budget/last/{u}", me.name())).get("monthlyNet").asDouble();

        Map<String, Object> detailed = quiz(me);
        detailed.put("housing", Map.of("situation", "Renting", "totalRent", 2400, "people", 3, "utilitiesIncluded", true));
        detailed.put("work", Map.of("arrangement", "hybrid", "commuteMonthly", 186, "commuteSummary", "drive, 3 days/week"));
        detailed.put("insurance", Map.of("payFrequency", 26, "health", 60, "dental", 8, "vision", 2));
        detailed.put("hasDebt", true);
        detailed.put("debts", List.of(
                Map.of("name", "Card", "principal", 2000, "apr", 24, "minPayment", 75, "dueDate", LocalDate.now().plusDays(10) + "T12:00:00Z"),
                Map.of("name", "Student loan", "principal", 30000, "apr", 5, "minPayment", 320, "dueDate", LocalDate.now().plusMonths(5) + "T12:00:00Z")));
        JsonNode budget = ok(postJson(me, "/api/llm/budget", detailed));

        ArgumentCaptor<String> prompt = ArgumentCaptor.forClass(String.class);
        verify(openAIService, times(2)).generateBudget(prompt.capture());
        String sent = prompt.getValue();
        assertThat(sent).contains("Allocate $800.00 to Rent").contains("Allocate $186.00 to Commute")
                .contains("Allocate $75.00 to Debt - Card")          // the minimum the app sent
                .doesNotContain("Debt - Student loan,")               // not a category yet
                .contains("payments don't start until")
                .contains("included in their rent").contains("before taxes");
        assertThat(sent).doesNotContain("Health Insurance");
        assertThat(budget.get("Debt - Card").asDouble()).isEqualTo(75.0);   // enforced even though the AI left it out
        assertThat(budget.has("Debt - Student loan")).isFalse();

        // $70 a paycheck before taxes: take-home goes down by less than $70 × 26 ÷ 12 (taxes are lower too)
        double netWithInsurance = ok(getAs(me, "/api/llm/budget/last/{u}", me.name())).get("monthlyNet").asDouble();
        assertThat(netWithInsurance).isLessThan(netWithoutInsurance).isGreaterThan(netWithoutInsurance - 70 * 26 / 12.0);
    }

    @Test
    @DisplayName("Commute prices: estimated once per place, then the same numbers from the cache")
    void commutePrices() throws Exception {
        when(openAIService.estimateJson(anyString(), contains("gallon"))).thenReturn("{\"pricePerGallon\": 3.19}");
        when(openAIService.estimateJson(anyString(), contains("toll"))).thenReturn("{\"oneWay\": 4.5}");
        User me = newUser();
        Map<String, Object> body = Map.of("mode", "drive", "homeState", "Virginia", "homeCity", "Fairfax",
                "workPlace", "Washington, DC", "electric", false, "routeHasTolls", true);
        JsonNode first = ok(postJson(me, "/api/tools/commute-prices", body));
        JsonNode second = ok(postJson(me, "/api/tools/commute-prices", body));
        assertThat(first.get("gas").get("pricePerGallon").asDouble()).isEqualTo(3.19);
        assertThat(second.get("tolls").get("oneWay").asDouble()).isEqualTo(4.5);
        verify(openAIService, times(1)).estimateJson(anyString(), contains("gallon"));
    }

    @Test
    @DisplayName("Tune the budget: needs a linked bank and a month of spending; suggestions apply only when accepted")
    void retune() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/budget", Map.of("username", me.name(), "type", "monthly",
                "budget", Map.of("Groceries", 250, "Eating Out", 200, "Rent", 1200, "Savings", 300))));
        assertThat(ok(getAs(me, "/api/budget/{u}/retune", me.name())).get("ready").asBoolean()).isFalse(); // no bank

        tokenStore.saveAccessToken(me.name().toLowerCase(), "item-1", "access-sandbox-test");
        assertThat(ok(getAs(me, "/api/budget/{u}/retune", me.name())).get("ready").asBoolean()).isFalse(); // no full month yet

        String lastMonth = YearMonth.now().minusMonths(1) + "-10";
        ok(postJson(me, "/api/costs/add-dated", Map.of("username", me.name(), "type", "monthly", "date", lastMonth,
                "costs", Map.of("Groceries", 340, "Eating Out", 120, "Rent", 1200))));
        // the budget was made today: last month was before it, so nothing yet; the first check is after next month
        JsonNode early = ok(getAs(me, "/api/budget/{u}/retune", me.name()));
        assertThat(early.get("ready").asBoolean()).isFalse();
        assertThat(early.get("firstCheck").asText()).isEqualTo(YearMonth.now().plusMonths(2).atDay(1).toString());

        // with the budget made before last month began, last month counts
        s3.putObject(b -> b.bucket("plotline-database-bucket").key("users/" + me.name().toLowerCase() + "/budget-changed.json"),
                software.amazon.awssdk.core.sync.RequestBody.fromString("{\"date\": \"" + YearMonth.now().minusMonths(2).atDay(1) + "\"}"));
        JsonNode result = ok(getAs(me, "/api/budget/{u}/retune", me.name()));
        assertThat(result.get("ready").asBoolean()).isTrue();
        JsonNode suggestion = result.get("suggestions").get(0);
        assertThat(suggestion.get("category").asText()).isEqualTo("Groceries");
        // take-home isn't known (no quiz), so only what Eating Out doesn't use pays for the raise
        assertThat(suggestion.get("kind").asText()).isEqualTo("partial");
        assertThat(budgetAmount(me, "Groceries")).isEqualTo(250); // nothing changed yet

        ok(postJson(me, "/api/budget/" + me.name() + "/retune/apply", Map.of("changes", suggestion.get("changes"))));
        assertThat(budgetAmount(me, "Groceries")).isEqualTo(330);
        assertThat(budgetAmount(me, "Eating Out")).isEqualTo(120);
    }

    private double budgetAmount(User me, String category) throws Exception {
        return ok(getAs(me, "/api/budget/{u}/{t}", me.name(), "monthly")).get("budget").get(category).asDouble();
    }

    @Test
    @DisplayName("Review: amounts with a reason each and take-home; known costs stay exact; every dollar assigned fills Savings")
    void detailedBudget() throws Exception {
        when(openAIService.generateBudget(anyString())).thenReturn("""
            {"budget": {"Rent": 900, "Groceries": 350, "Savings": 300, "Phone": 60},
             "why": {"Groceries": "1 person, cooks most nights, Virginia prices"}}
            """);
        when(openAIService.generateResponseLocalTaxes(anyString())).thenReturn("0");
        User me = newUser();
        Map<String, Object> q = quiz(me);
        q.put("withDetails", true);
        q.put("budgetingStyle", "everyDollar");
        q.put("housing", Map.of("situation", "Renting", "yourShare", 800));
        q.put("otherCosts", Map.of("phone", 45));
        JsonNode r = ok(postJson(me, "/api/llm/budget", q));

        assertThat(r.get("why").get("Groceries").asText()).contains("cooks most nights");
        assertThat(r.get("budget").get("Rent").asDouble()).isEqualTo(800.0);   // the AI said 900; rent is what they told us
        assertThat(r.get("budget").get("Phone").asDouble()).isEqualTo(45.0);
        double net = r.get("monthlyNet").asDouble();
        double total = 0;
        for (JsonNode v : r.get("budget")) total += v.asDouble();
        assertThat(Math.abs(total - net)).isLessThan(1.0);                     // every dollar assigned
        assertThat(r.get("budgetingStyle").asText()).isEqualTo("everyDollar");
        assertThat(r.get("fixed").toString()).contains("Rent").contains("Phone").doesNotContain("Groceries");
    }

    @Test
    @DisplayName("Plan in the quiz: debt lines are the minimums, more is Extra Debt Payment; Savings splits into the fund and goals")
    void planLines() throws Exception {
        when(openAIService.generateBudget(anyString())).thenReturn("""
            {"budget": {"Rent": 900, "Groceries": 350, "Transportation": 100, "Savings": 600, "Debt - Visa": 100}, "why": {}}
            """);
        when(openAIService.generateResponseLocalTaxes(anyString())).thenReturn("0");
        User me = newUser();
        Map<String, Object> q = quiz(me);
        q.put("withDetails", true);
        q.put("hasDebt", true);
        q.put("debts", List.of(Map.of("name", "Visa", "principal", 2000, "apr", 24, "minPayment", 40)));
        q.put("savings", Map.of("emergencySaved", 500, "emergencyMonths", 3, "goals",
                List.of(Map.of("name", "Trip", "target", 3000, "saved", 0, "targetDate", "2027-08-01", "monthlyNeeded", 150))));
        JsonNode r = ok(postJson(me, "/api/llm/budget", q));
        JsonNode budget = r.get("budget");
        assertThat(budget.get("Debt - Visa").asDouble()).isEqualTo(40.0);
        assertThat(budget.get("Extra Debt Payment").asDouble()).isEqualTo(60.0);   // the AI's $60 over the minimum
        assertThat(budget.get("Savings - Trip").asDouble()).isEqualTo(150.0);
        assertThat(budget.get("Emergency Fund").asDouble()).isEqualTo(450.0);      // the rest of the $600
        assertThat(budget.has("Savings")).isFalse();
        assertThat(r.get("why").get("Emergency Fund").asText()).contains("$500 of");

        // the planner's extra is kept as set; the AI's overpayment goes to savings instead
        q.put("extraDebtPayment", 200);
        JsonNode withExtra = ok(postJson(me, "/api/llm/budget", q));
        budget = withExtra.get("budget");
        assertThat(withExtra.get("why").get("Extra Debt Payment").asText()).contains("debt payoff planner");
        assertThat(budget.get("Extra Debt Payment").asDouble()).isEqualTo(200.0);
        assertThat(budget.get("Debt - Visa").asDouble()).isEqualTo(40.0);
        assertThat(budget.get("Emergency Fund").asDouble() + budget.get("Savings - Trip").asDouble()).isEqualTo(660.0);
    }

    @Test
    @DisplayName("Review flow: building saves nothing; Save stores the reviewed budget and the answers, replacing old edits")
    void reviewThenSave() throws Exception {
        when(openAIService.generateBudget(anyString())).thenReturn("""
            {"budget": {"Rent": 900, "Groceries": 350, "Savings": 300}, "why": {}}
            """);
        when(openAIService.generateResponseLocalTaxes(anyString())).thenReturn("0");
        User me = newUser();
        // an earlier budget they had edited
        ok(postJson(me, "/api/budget", Map.of("username", me.name(), "type", "monthly", "budget", Map.of("Rent", 700.0))));

        Map<String, Object> q = quiz(me);
        q.put("withDetails", true);
        JsonNode draft = ok(postJson(me, "/api/llm/budget", q));
        assertThat(draft.get("answers").get("monthlyNet").asDouble()).isGreaterThan(0);
        call(getAs(me, "/api/llm/budget/last/{u}", me.name()), 204);                       // answers not saved yet
        assertThat(ok(getAs(me, "/api/budget/{u}/monthly", me.name())).toString()).contains("700"); // still the old budget

        Map<String, Object> answers = new java.util.HashMap<>(q);
        answers.put("monthlyNet", draft.get("answers").get("monthlyNet").asDouble());
        answers.put("reviewOverrides", Map.of("Rent", 950));
        ok(postJson(me, "/api/llm/budget/save", Map.of("username", me.name(),
                "budget", Map.of("Rent", 950, "Groceries", 350, "Savings", 300), "answers", answers)));
        JsonNode budget = ok(getAs(me, "/api/budget/{u}/monthly", me.name()));
        assertThat(budget.toString()).contains("950").doesNotContain("700");
        JsonNode last = ok(getAs(me, "/api/llm/budget/last/{u}", me.name()));
        assertThat(last.get("monthlyNet").asDouble()).isGreaterThan(0);
        assertThat(last.has("withDetails")).isFalse();
        assertThat(last.has("reviewOverrides")).isFalse();

        // someone else's budget can't be saved
        User other = newUser();
        call(postJson(other, "/api/llm/budget/save", Map.of("username", me.name(), "budget", Map.of("Rent", 1))), 403);
    }

    @Test
    @DisplayName("Gas and Transportation are at least what driving and the commute cost; no Commute line")
    void drivingMinimums() throws Exception {
        when(openAIService.generateBudget(anyString())).thenReturn("""
            {"budget": {"Gas": 18, "Transportation": 300, "Commute": 327, "Groceries": 400}, "why": {}}
            """);
        when(openAIService.generateResponseLocalTaxes(anyString())).thenReturn("0");
        User me = newUser();
        Map<String, Object> q = quiz(me);
        q.put("withDetails", true);
        q.put("work", Map.of("arrangement", "office", "mode", "drive", "commuteMonthly", 327, "commuteGas", 141, "commuteOther", 186));
        q.put("otherCosts", Map.of("otherGas", 18.2));
        JsonNode r = ok(postJson(me, "/api/llm/budget", q));
        assertThat(r.get("budget").get("Gas").asDouble()).isEqualTo(160.0);            // raised to 141 + 18.20
        assertThat(r.get("budget").get("Transportation").asDouble()).isEqualTo(300.0); // already more than 186
        assertThat(r.get("budget").has("Commute")).isFalse();
        // the explanations say what each covers
        assertThat(r.get("why").get("Gas").asText()).isEqualTo("Fuel for all your driving ($141 to get to work + $18 for other driving).");
        assertThat(r.get("why").get("Transportation").asText())
                .startsWith("Getting around besides gas: parking, tolls, Uber/Lyft, buses and trains. Includes $186 a month for getting to work");
    }

    @Test
    @DisplayName("Regenerate from the budget page: exactly its categories, its amounts kept, new ones sized from spending")
    void regenerateExact() throws Exception {
        when(openAIService.generateBudget(anyString())).thenReturn("""
            {"budget": {"Groceries": 400, "Travel": 250, "Rent": 1100, "Gas": 10}, "why": {}}
            """);
        when(openAIService.generateResponseLocalTaxes(anyString())).thenReturn("0");
        User me = newUser();
        Map<String, Object> q = quiz(me);
        q.put("withDetails", true);
        q.put("exactCategories", true);
        q.put("categories", List.of("Groceries", "Travel", "Eating Out"));        // Rent and Gas were removed on the page
        q.put("newCategories", List.of("Travel"));
        q.put("reviewOverrides", Map.of("Groceries", 450, "Eating Out", 300));
        q.put("housing", Map.of("situation", "Renting", "yourShare", 1100));
        q.put("work", Map.of("arrangement", "office", "mode", "drive", "commuteGas", 120, "commuteOther", 0));
        JsonNode r = ok(postJson(me, "/api/llm/budget", q));
        assertThat(r.get("budget").get("Groceries").asDouble()).isEqualTo(450.0);   // kept
        assertThat(r.get("budget").get("Eating Out").asDouble()).isEqualTo(300.0);
        assertThat(r.get("budget").has("Gas")).isFalse();                         // removed stays removed (no minimum added)

        ArgumentCaptor<String> prompt = ArgumentCaptor.forClass(String.class);
        verify(openAIService, org.mockito.Mockito.atLeastOnce()).generateBudget(prompt.capture());
        String sent = prompt.getValue();
        assertThat(sent).contains("They just added these categories: Travel").contains("Don't size them to fill leftover money");
        assertThat(sent.substring(sent.indexOf("Use ONLY these categories"), sent.indexOf("The user already knows")))
                .doesNotContain("Rent").doesNotContain("Gas");
    }

    @Test
    @DisplayName("A budget never plans more than take-home: wants are lowered (bills kept), and high real spending is flagged")
    void fitsTakeHome() throws Exception {
        when(openAIService.generateBudget(anyString())).thenReturn("""
            {"budget": {"Rent": 1100, "Shopping": 4000, "Eating Out": 3000, "Groceries": 400, "Savings": 300}, "why": {}}
            """);
        when(openAIService.generateResponseLocalTaxes(anyString())).thenReturn("0");
        User me = newUser();
        Map<String, Object> q = quiz(me);
        q.put("withDetails", true);
        q.put("housing", Map.of("situation", "Renting", "yourShare", 1100));
        q.put("bankAverages", Map.of("Shopping", 2000, "Groceries", 410));
        JsonNode r = ok(postJson(me, "/api/llm/budget", q));
        double net = r.get("monthlyNet").asDouble(), total = 0;
        for (JsonNode v : r.get("budget")) total += v.asDouble();
        assertThat(total).isLessThanOrEqualTo(net + 0.5);
        assertThat(r.get("budget").get("Rent").asDouble()).isEqualTo(1100.0);         // a bill they gave: untouched
        assertThat(r.get("budget").get("Groceries").asDouble()).isEqualTo(400.0);      // a need: untouched
        assertThat(r.get("budget").get("Shopping").asDouble()).isLessThan(4000.0);
        assertThat(r.get("why").get("Shopping").asText()).contains("Lowered to fit your take-home");
        JsonNode over = r.get("overspending");
        assertThat(over.size()).isEqualTo(1);
        assertThat(over.get(0).get("category").asText()).isEqualTo("Shopping");      // usually $2,000, more than planned now
        assertThat(over.get(0).get("usual").asDouble()).isEqualTo(2000.0);
        assertThat(r.get("usualTotal").asDouble()).isEqualTo(2410.0);
    }

    @Test
    @DisplayName("Rebuild with AI: amounts changed on the review screen stay exactly as typed")
    void reviewOverrides() throws Exception {
        when(openAIService.generateBudget(anyString())).thenReturn("""
            {"budget": {"Rent": 900, "Groceries": 350, "Eating Out": 300, "Savings": 300}, "why": {}}
            """);
        when(openAIService.generateResponseLocalTaxes(anyString())).thenReturn("0");
        User me = newUser();
        Map<String, Object> q = quiz(me);
        q.put("withDetails", true);
        q.put("housing", Map.of("situation", "Renting", "yourShare", 800));
        q.put("reviewOverrides", Map.of("Rent", 850, "Eating Out", 150));
        JsonNode r = ok(postJson(me, "/api/llm/budget", q));
        assertThat(r.get("budget").get("Rent").asDouble()).isEqualTo(850.0);       // the review edit wins over the quiz answer
        assertThat(r.get("budget").get("Eating Out").asDouble()).isEqualTo(150.0);
        assertThat(r.get("fixed").toString()).contains("Eating Out");
    }

    @Test
    @DisplayName("Bank summary: monthly spending by category from Plaid, without transfers or card payments; refunds lower their category")
    @SuppressWarnings("unchecked")
    void spendingSummary() throws Exception {
        User me = newUser();
        assertThat(ok(getAs(me, "/api/plaid/spending-summary/{u}", me.name())).get("linked").asBoolean()).isFalse();
        tokenStore.saveAccessToken(me.name().toLowerCase(), "item-1", "access-sandbox-test");

        java.util.function.BiFunction<String, Double, com.plaid.client.model.Transaction> txn = (primaryAndDetailed, amount) -> {
            String[] parts = primaryAndDetailed.split("\\|");
            return new com.plaid.client.model.Transaction().amount(amount).pending(false).name(parts[2])
                    .date(LocalDate.now().minusDays(Long.parseLong(parts[3])))
                    .personalFinanceCategory(new com.plaid.client.model.PersonalFinanceCategory().primary(parts[0]).detailed(parts[1]));
        };
        var body = new com.plaid.client.model.TransactionsGetResponse().totalTransactions(7).transactions(List.of(
                txn.apply("ENTERTAINMENT|ENTERTAINMENT_TV_AND_MOVIES|NETFLIX|40", 15.49),
                txn.apply("ENTERTAINMENT|ENTERTAINMENT_TV_AND_MOVIES|NETFLIX|9", 15.49),
                txn.apply("FOOD_AND_DRINK|FOOD_AND_DRINK_GROCERIES|KROGER|85", 300.0),
                txn.apply("FOOD_AND_DRINK|FOOD_AND_DRINK_GROCERIES|KROGER|10", 300.0),
                txn.apply("FOOD_AND_DRINK|FOOD_AND_DRINK_RESTAURANTS|CHIPOTLE|20", 90.0),
                txn.apply("LOAN_PAYMENTS|LOAN_PAYMENTS_CREDIT_CARD_PAYMENT|CARD PAYMENT|15", 1200.0),
                txn.apply("FOOD_AND_DRINK|FOOD_AND_DRINK_GROCERIES|KROGER REFUND|5", -40.0)));
        retrofit2.Call<com.plaid.client.model.TransactionsGetResponse> call = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(call.execute()).thenReturn(retrofit2.Response.success(body));
        when(plaidApi.transactionsGet(org.mockito.ArgumentMatchers.any())).thenReturn(call);

        JsonNode r = ok(getAs(me, "/api/plaid/spending-summary/{u}", me.name()));
        assertThat(r.get("ready").asBoolean()).isTrue();
        double months = r.get("months").asDouble();                  // ~85 days of history
        assertThat(months).isBetween(2.7, 2.9);
        assertThat(r.get("averages").get("Groceries").asDouble()).isEqualTo(Math.round(560 / months)); // 600 bought, 40 refunded
        assertThat(r.get("averages").get("Eating Out").asDouble()).isEqualTo(Math.round(90 / months));
        assertThat(r.get("averages").has("Miscellaneous")).isFalse(); // the card payment isn't spending
        // what the Subscriptions average is made of
        JsonNode charge = r.get("subscriptionCharges").get(0);
        assertThat(charge.get("name").asText()).isEqualTo("NETFLIX");
        assertThat(charge.get("amount").asDouble()).isEqualTo(15.49);
        assertThat(charge.get("times").asInt()).isEqualTo(2);
        assertThat(charge.get("dayOfMonth").asInt()).isEqualTo(LocalDate.now().minusDays(9).getDayOfMonth());
    }
}
