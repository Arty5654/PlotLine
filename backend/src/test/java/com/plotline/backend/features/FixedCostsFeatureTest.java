package com.plotline.backend.features;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import com.fasterxml.jackson.databind.JsonNode;
import com.plaid.client.model.PersonalFinanceCategory;
import com.plaid.client.model.Transaction;
import com.plaid.client.model.TransactionsSyncResponse;
import com.plotline.backend.plaid.TokenStore;

/** Fixed costs from the quiz, counted once; the quiz's 90 days of transactions in Monthly Costs. */
class FixedCostsFeatureTest extends FeatureTestBase {

    @Autowired TokenStore tokenStore;
    @Autowired com.plotline.backend.plaid.PlaidCursorStore plaidCursorStore;

    private void saveQuiz(User me, Map<String, Object> budget) throws Exception {
        ok(postJson(me, "/api/llm/budget/save", Map.of("username", me.name(), "budget", budget, "answers", Map.of("monthlyNet", 5000))));
    }

    private JsonNode fixed(User me) throws Exception {
        return ok(getAs(me, "/api/costs/fixed/{u}", me.name()));
    }

    @Test
    @DisplayName("Saving the quiz adds its fixed lines (savings, investing, bills, debt minimums), not the rest or subscriptions")
    void fromQuiz() throws Exception {
        User me = newUser();
        // one they made themselves keeps its amount
        ok(postJson(me, "/api/costs/fixed/" + me.name(), Map.of("category", "Rent", "amount", 1400)));
        saveQuiz(me, Map.of("Savings", 500, "Roth IRA", 300, "Brokerage", 200, "Rent", 1450, "Phone", 45,
                "Subscriptions", 38, "Debt - Chase Card", 60, "Groceries", 400, "Eating Out", 250, "Utilities", 140));
        Map<String, Double> byCategory = new java.util.HashMap<>();
        fixed(me).forEach(f -> byCategory.put(f.get("category").asText(), f.get("amount").asDouble()));
        assertThat(byCategory).containsEntry("Savings", 500.0).containsEntry("Roth IRA", 300.0).containsEntry("Brokerage", 200.0)
                .containsEntry("Phone", 45.0).containsEntry("Debt - Chase Card", 60.0)
                .containsEntry("Rent", 1400.0)                     // theirs, left alone
                .doesNotContainKeys("Groceries", "Eating Out", "Utilities",   // utilities change month to month
                        "Subscriptions");                          // counted as they're charged

        // removing one the quiz added: the next quiz doesn't add it back; a dropped quiz line goes away
        String brokerageId = null;
        for (JsonNode f : fixed(me)) if (f.get("category").asText().equals("Brokerage")) brokerageId = f.get("id").asText();
        ok(deleteAs(me, "/api/costs/fixed/{u}/{id}", me.name(), brokerageId));
        saveQuiz(me, Map.of("Savings", 600, "Brokerage", 200, "Rent", 1450, "Groceries", 400));
        java.util.Set<String> now = new java.util.HashSet<>();
        fixed(me).forEach(f -> now.add(f.get("category").asText() + "=" + f.get("amount").asDouble()));
        assertThat(now).contains("Savings=600.0", "Rent=1400.0").noneMatch(c -> c.startsWith("Brokerage") || c.startsWith("Phone"));
    }

    @Test
    @DisplayName("Subscriptions are never a fixed cost: refused as one, and an old fixed entry stops counting")
    void subscriptionsNotFixed() throws Exception {
        User me = newUser();
        saveQuiz(me, Map.of("Rent", 1450, "Subscriptions", 30, "Savings", 300));
        call(postJson(me, "/api/costs/fixed/" + me.name(), Map.of("category", "Subscriptions", "amount", 47.98)), 400);

        // one saved by an older version of the app
        String user = me.name().toLowerCase();
        byte[] old = objectMapper.writeValueAsBytes(java.util.List.of(
                Map.of("id", "old-subs", "category", "Subscriptions", "amount", 30, "source", "quiz"),
                Map.of("id", "rent", "category", "Rent", "amount", 1450)));
        s3.putObject(software.amazon.awssdk.services.s3.model.PutObjectRequest.builder().bucket("plotline-database-bucket").key("users/" + user + "/fixed_costs.json").build(),
                software.amazon.awssdk.core.sync.RequestBody.fromBytes(old));
        java.util.Set<String> categories = new java.util.HashSet<>();
        fixed(me).forEach(f -> categories.add(f.get("category").asText()));
        assertThat(categories).contains("Rent").doesNotContain("Subscriptions");

        // what was charged counts, like any category
        String month = YearMonth.now().toString();
        ok(postJson(me, "/api/costs/add-dated", Map.of("username", me.name(), "type", "monthly", "date", month + "-05",
                "costs", Map.of("Subscriptions", 17.99))));
        JsonNode totals = ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", month)).get("totals");
        assertThat(totals.get("Subscriptions").asDouble()).isEqualTo(17.99);

        // the budget line can be set on its own (Track Subscriptions)
        JsonNode budget = ok(postJson(me, "/api/budget/" + me.name() + "/line", Map.of("line", "Subscriptions", "amount", 41.97))).get("budget");
        assertThat(budget.get("Subscriptions").asDouble()).isEqualTo(41.97);
        assertThat(budget.get("Rent").asDouble()).isEqualTo(1450.0);
        call(postJson(newUser(), "/api/budget/" + me.name() + "/line", Map.of("line", "Subscriptions", "amount", 1)), 403);
    }

    @Test
    @DisplayName("A fixed cost is counted once in a month, even if spending was also recorded in that category")
    void countedOnce() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/costs/fixed/" + me.name(), Map.of("category", "Rent", "amount", 1450)));
        String month = YearMonth.now().toString();
        ok(postJson(me, "/api/costs/add-dated", Map.of("username", me.name(), "type", "monthly", "date", month + "-01",
                "costs", Map.of("Rent", 1450, "Groceries", 120))));
        JsonNode totals = ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", month)).get("totals");
        assertThat(totals.get("Rent").asDouble()).isEqualTo(1450.0);          // not 2,900
        assertThat(totals.get("Groceries").asDouble()).isEqualTo(120.0);
    }

    @Test
    @DisplayName("Feedback compares with last month, or the 3- or 6-month average, and has a 6-month history")
    void feedback() throws Exception {
        User me = newUser();
        YearMonth now = YearMonth.now();
        double[] spent = {300, 400, 500, 600};                               // 4, 3, 2 and 1 months ago
        for (int i = 4; i >= 1; i--) {
            ok(postJson(me, "/api/costs/add-dated", Map.of("username", me.name(), "type", "monthly", "date", now.minusMonths(i) + "-05",
                    "costs", Map.of("Groceries", spent[4 - i]))));
        }
        ok(postJson(me, "/api/costs/add-dated", Map.of("username", me.name(), "type", "monthly", "date", now + "-05",
                "costs", Map.of("Groceries", 450))));
        JsonNode last = ok(getAs(me, "/api/costs/feedback/{u}", me.name()).param("month", now.toString()).param("compare", "last"));
        assertThat(last.get("totalPrevious").asDouble()).isEqualTo(600.0);
        JsonNode three = ok(getAs(me, "/api/costs/feedback/{u}", me.name()).param("month", now.toString()).param("compare", "3"));
        assertThat(three.get("totalPrevious").asDouble()).isEqualTo(500.0);    // (600 + 500 + 400) / 3
        assertThat(three.get("monthsCompared").asInt()).isEqualTo(3);
        JsonNode history = three.get("history");
        assertThat(history.size()).isEqualTo(6);
        assertThat(history.get(5).get("total").asDouble()).isEqualTo(450.0);  // this month last
        assertThat(history.get(0).get("tracked").asBoolean()).isFalse();      // 5 months ago: nothing tracked
    }

    private int trophy(User me, String id) throws Exception {
        for (JsonNode t : ok(getAs(me, "/profile/get-trophies").param("username", me.name()))) {
            if (t.get("id").asText().equals(id)) return t.get("progress").asInt();
        }
        return -1;
    }

    @Test
    @DisplayName("Monthly trophies: once per finished month against the real budget, however often Feedback is opened")
    void trophiesOncePerMonth() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/budget", Map.of("username", me.name(), "type", "monthly",
                "budget", Map.of("Groceries", 400.0, "Eating Out", 200.0, "Rent", 1000.0))));
        YearMonth last = YearMonth.now().minusMonths(1), before = last.minusMonths(1);
        ok(postJson(me, "/api/costs/add-dated", Map.of("username", me.name(), "type", "monthly", "date", before + "-10",
                "costs", Map.of("Groceries", 350, "Eating Out", 220))));
        ok(postJson(me, "/api/costs/add-dated", Map.of("username", me.name(), "type", "monthly", "date", last + "-10",
                "costs", Map.of("Groceries", 380, "Eating Out", 150, "Rent", 1000))));      // $1,530 of $1,600
        ok(postJson(me, "/api/costs/add-dated", Map.of("username", me.name(), "type", "monthly", "date", YearMonth.now() + "-01",
                "costs", Map.of("Groceries", 20))));                                        // this month: not judged yet
        for (int i = 0; i < 5; i++) {
            ok(getAs(me, "/api/costs/feedback/{u}", me.name()).param("month", YearMonth.now().toString()).param("compare", i % 2 == 0 ? "3" : "last"));
        }
        assertThat(trophy(me, "monthly-budget-met")).isEqualTo(1);
        assertThat(trophy(me, "budget-pacer")).isZero();          // 95.6% of the budget: not 5% under
        assertThat(trophy(me, "healthy-eater")).isEqualTo(1);     // eating out down, groceries up
    }

    @Test
    @DisplayName("Over-counted monthly trophies start over once per account; progress after that is kept")
    void overCountedReset() throws Exception {
        // trophies as an account had them before the fix: Monthly Budgetor at 14 (Diamond)
        JsonNode defaults = ok(getAs(newUser(), "/profile/get-trophies").param("username", newUser().name()));
        var inflated = (com.fasterxml.jackson.databind.node.ArrayNode) defaults.deepCopy();
        for (JsonNode t : inflated) {
            if (t.get("id").asText().equals("monthly-budget-met")) {
                ((com.fasterxml.jackson.databind.node.ObjectNode) t).put("progress", 14).put("level", 4);
            }
        }
        User me = newUser();
        s3.putObject(b -> b.bucket("plotline-database-bucket").key("users/" + me.name().toLowerCase() + "/trophies.json"),
                software.amazon.awssdk.core.sync.RequestBody.fromString(inflated.toString()));
        assertThat(trophy(me, "monthly-budget-met")).isZero();
        ok(postJson(me, "/profile/increment-trophies?username=" + me.name() + "&trophyId=monthly-budget-met&amount=1", Map.of()));
        assertThat(trophy(me, "monthly-budget-met")).isEqualTo(1);   // not reset again
    }

    @Test
    @DisplayName("Bank sync: the quiz's 90 days come in; transactions in fixed-cost categories are skipped")
    @SuppressWarnings("unchecked")
    void syncSkipsFixed() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        tokenStore.saveAccessToken(user, "item-1", "access-test");
        ok(postJson(me, "/api/costs/fixed/" + me.name(), Map.of("category", "Rent", "amount", 1450)));
        java.util.function.BiFunction<String, Integer, Transaction> txn = (kind, daysAgo) -> new Transaction()
                .transactionId(kind + daysAgo).name(kind.equals("rent") ? "BRIDGE APARTMENTS" : "KROGER").amount(kind.equals("rent") ? 1450.0 : 80.0)
                .pending(false).accountId("acct").date(LocalDate.now().minusDays(daysAgo))
                .personalFinanceCategory(kind.equals("rent")
                        ? new PersonalFinanceCategory().primary("RENT_AND_UTILITIES").detailed("RENT_AND_UTILITIES_RENT")
                        : new PersonalFinanceCategory().primary("FOOD_AND_DRINK").detailed("FOOD_AND_DRINK_GROCERIES"));
        var body = new TransactionsSyncResponse().added(List.of(txn.apply("rent", 3), txn.apply("groceries", 5), txn.apply("groceries", 70)))
                .modified(List.of()).removed(List.of()).hasMore(false).nextCursor("c1");
        retrofit2.Call<TransactionsSyncResponse> call = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(call.execute()).thenReturn(retrofit2.Response.success(body));
        when(plaidApi.transactionsSync(any())).thenReturn(call);

        JsonNode result = ok(postJson(me, "/api/plaid/sync", Map.of("username", user, "days", 90)));
        assertThat(result.get("added").asInt()).isEqualTo(2);                // both grocery trips, 70 days ago too
        assertThat(result.get("skippedFixed").asInt()).isEqualTo(1);         // the rent payment
    }

    @Test
    @DisplayName("Quiz import: 90 days by date even after earlier syncs; picked accounts only; nothing held back; nothing counted twice")
    @SuppressWarnings("unchecked")
    void importHistory() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        tokenStore.saveAccessToken(user, "item-1", "access-test");
        tokenStore.saveSelectedAccounts(user, "item-1", List.of("acct"));
        ok(postJson(me, "/api/costs/fixed/" + me.name(), Map.of("category", "Rent", "amount", 1450)));
        java.util.function.Function<Object[], Transaction> txn = a -> {
            Transaction t = new Transaction().transactionId((String) a[0]).name((String) a[1]).amount((Double) a[2])
                    .pending(false).accountId((String) a[3]).date(LocalDate.now().minusDays((Integer) a[4]));
            if (a[5] != null) t.personalFinanceCategory(new PersonalFinanceCategory().primary((String) a[5]).detailed((String) a[6]));
            return t;
        };
        Transaction recent = txn.apply(new Object[]{"g5", "KROGER", 30.0, "acct", 5, "FOOD_AND_DRINK", "FOOD_AND_DRINK_GROCERIES"});
        Transaction mystery = txn.apply(new Object[]{"y20", "SOME SHOP INC", 40.0, "acct", 20, null, null});
        List<Transaction> all = List.of(recent, mystery,
                txn.apply(new Object[]{"g5b", "SAFEWAY", 12.0, "acct", 5, "FOOD_AND_DRINK", "FOOD_AND_DRINK_GROCERIES"}),
                txn.apply(new Object[]{"g75", "KROGER", 80.0, "acct", 75, "FOOD_AND_DRINK", "FOOD_AND_DRINK_GROCERIES"}),
                txn.apply(new Object[]{"r75", "KROGER", -10.0, "acct", 75, "FOOD_AND_DRINK", "FOOD_AND_DRINK_GROCERIES"}),
                txn.apply(new Object[]{"rent3", "BRIDGE APARTMENTS", 1450.0, "acct", 3, "RENT_AND_UTILITIES", "RENT_AND_UTILITIES_RENT"}),
                txn.apply(new Object[]{"x20", "SOMEWHERE LLC", 25.0, "acct", 20, null, null}),
                txn.apply(new Object[]{"other75", "KROGER", 500.0, "not-picked", 75, "FOOD_AND_DRINK", "FOOD_AND_DRINK_GROCERIES"}),
                txn.apply(new Object[]{"tr75", "TRANSFER TO SAVINGS", 900.0, "acct", 75, "TRANSFER_OUT", "TRANSFER_OUT_SAVINGS"}),
                txn.apply(new Object[]{"pend75", "KROGER", 60.0, "acct", 75, "FOOD_AND_DRINK", "FOOD_AND_DRINK_GROCERIES"}).pending(true));

        // an earlier sync from Monthly Costs brought in the recent trip (moving the cursor past the rest)
        // and handed out the charge it couldn't sort, which they assigned to Shopping
        retrofit2.Call<TransactionsSyncResponse> syncCall = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(syncCall.execute()).thenReturn(retrofit2.Response.success(new TransactionsSyncResponse()
                .added(List.of(recent)).modified(List.of()).removed(List.of()).hasMore(false).nextCursor("c1")));
        when(plaidApi.transactionsSync(any())).thenReturn(syncCall);
        assertThat(ok(postJson(me, "/api/plaid/sync", Map.of("username", user))).get("added").asInt()).isEqualTo(1);
        ok(postJson(me, "/api/costs/assign", Map.of("username", user, "assignments", List.of(Map.of("txnId", "y20",
                "date", mystery.getDate().toString(), "name", "SOME SHOP INC", "category", "Shopping", "amount", 40.0)))));

        retrofit2.Call<com.plaid.client.model.TransactionsGetResponse> getCall = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(getCall.execute()).thenAnswer(x -> retrofit2.Response.success(
                new com.plaid.client.model.TransactionsGetResponse().totalTransactions(all.size()).transactions(all)));
        when(plaidApi.transactionsGet(any())).thenReturn(getCall);

        JsonNode result = ok(postJson(me, "/api/plaid/import-history", Map.of("username", user, "days", 90)));
        assertThat(result.get("added").asInt()).isEqualTo(4);         // the second trip that day, the 75-day-old trip and its refund, the unlabeled charge
        assertThat(result.get("skippedSeen").asInt()).isEqualTo(3);   // the synced trip, the hand-assigned charge, the refund the catch-up just brought in
        assertThat(result.get("skippedFixed").asInt()).isEqualTo(1);  // rent: a fixed cost
        assertThat(ok(postJson(me, "/api/plaid/import-history", Map.of("username", user))).get("added").asInt()).isZero(); // not twice

        // the bank later updates the synced trip: not counted again
        when(syncCall.execute()).thenReturn(retrofit2.Response.success(new TransactionsSyncResponse()
                .added(List.of()).modified(List.of(recent)).removed(List.of()).hasMore(false).nextCursor("c2")));
        assertThat(ok(postJson(me, "/api/plaid/sync", Map.of("username", user))).get("modified").asInt()).isZero();

        // each month holds exactly what was counted: both trips on the same day (added, not replaced),
        // not the other account, the transfer or the pending one; rent counted once
        Map<String, Double> expected = new java.util.TreeMap<>();
        for (Object[] c : new Object[][]{{5, 30.0}, {5, 12.0}, {75, 80.0}, {75, -10.0}, {20, 25.0}, {20, 40.0}})
            expected.merge(YearMonth.from(LocalDate.now().minusDays((Integer) c[0])).toString(), (Double) c[1], Double::sum);
        for (var month : expected.entrySet()) {
            JsonNode totals = ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", month.getKey())).get("totals");
            double flexible = 0;
            for (var f : (Iterable<Map.Entry<String, JsonNode>>) totals::fields) if (!f.getKey().equalsIgnoreCase("Rent")) flexible += f.getValue().asDouble();
            assertThat(flexible).as(month.getKey()).isEqualTo(month.getValue());
            assertThat(totals.get("Rent").asDouble()).isEqualTo(1450.0);
        }
        // what nothing could label is in Miscellaneous, not held back for assigning
        JsonNode misc = ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", YearMonth.from(LocalDate.now().minusDays(20)).toString())).get("totals");
        assertThat(misc.path("Miscellaneous").asDouble()).isEqualTo(25.0);
        assertThat(misc.path("Shopping").asDouble()).isEqualTo(40.0);
    }

    @Test
    @DisplayName("Bank sync: a charge the bank reverses comes back out of Monthly Costs; other charges that day stay")
    @SuppressWarnings("unchecked")
    void reversedCharge() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        tokenStore.saveAccessToken(user, "item-1", "access-test");
        LocalDate day = LocalDate.now().minusDays(2);
        java.util.function.BiFunction<String, Double, Transaction> trip = (id, amount) -> new Transaction().transactionId(id).name("KROGER")
                .amount(amount).pending(false).accountId("acct").date(day)
                .personalFinanceCategory(new PersonalFinanceCategory().primary("FOOD_AND_DRINK").detailed("FOOD_AND_DRINK_GROCERIES"));
        retrofit2.Call<TransactionsSyncResponse> call = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(call.execute()).thenReturn(retrofit2.Response.success(new TransactionsSyncResponse()
                .added(List.of(trip.apply("keep", 30.0), trip.apply("reversed", 45.0))).modified(List.of()).removed(List.of()).hasMore(false).nextCursor("c1")));
        when(plaidApi.transactionsSync(any())).thenReturn(call);
        ok(postJson(me, "/api/plaid/sync", Map.of("username", user)));
        String month = YearMonth.from(day).toString();
        java.util.function.Supplier<Double> monthTotal = () -> {
            try {
                double sum = 0;
                for (var f : (Iterable<Map.Entry<String, JsonNode>>) ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", month)).get("totals")::fields)
                    sum += f.getValue().asDouble();
                return sum;
            } catch (Exception e) { throw new RuntimeException(e); }
        };
        assertThat(monthTotal.get()).isEqualTo(75.0);

        // the bank takes back the $45 charge (and drops a pending one that was never counted)
        when(call.execute()).thenReturn(retrofit2.Response.success(new TransactionsSyncResponse().added(List.of()).modified(List.of())
                .removed(List.of(new com.plaid.client.model.RemovedTransaction().transactionId("reversed"),
                        new com.plaid.client.model.RemovedTransaction().transactionId("pending-never-counted")))
                .hasMore(false).nextCursor("c2")));
        assertThat(ok(postJson(me, "/api/plaid/sync", Map.of("username", user))).get("removed").asInt()).isEqualTo(1);
        assertThat(monthTotal.get()).isEqualTo(30.0);
        JsonNode txns = ok(getAs(me, "/api/costs/transactions/{u}", me.name()).param("month", month));
        assertThat(txns.toString()).contains("keep").doesNotContain("reversed");
    }

    private static Transaction credit(String id, String name, double amount, String primary, String detailed) {
        Transaction t = new Transaction().transactionId(id).name(name).merchantName(name).amount(amount).pending(false)
                .accountId("acct").date(LocalDate.now().minusDays(1));
        if (primary != null) t.personalFinanceCategory(new PersonalFinanceCategory().primary(primary).detailed(detailed));
        return t;
    }

    @Test
    @DisplayName("Refunds lower their category (sync, edits, reversal); pay, transfers and unlabeled credits don't")
    @SuppressWarnings("unchecked")
    void refunds() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        tokenStore.saveAccessToken(user, "item-1", "access-test");
        retrofit2.Call<TransactionsSyncResponse> call = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(call.execute()).thenReturn(retrofit2.Response.success(new TransactionsSyncResponse().added(List.of(
                credit("buy", "TARGET", 50.0, "GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_SUPERSTORES"),
                credit("refund", "TARGET", -20.0, "GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_SUPERSTORES"),
                credit("pay", "ACME PAYROLL", -1000.0, "INCOME", "INCOME_WAGES"),
                credit("xfer", "FROM SAVINGS", -200.0, "TRANSFER_IN", "TRANSFER_IN_ACCOUNT_TRANSFER"),
                credit("mystery", "CREDIT 0042", -15.0, null, null)))
                .modified(List.of()).removed(List.of()).hasMore(false).nextCursor("c1")));
        when(plaidApi.transactionsSync(any())).thenReturn(call);
        JsonNode synced = ok(postJson(me, "/api/plaid/sync", Map.of("username", user)));
        assertThat(synced.get("added").asInt()).isEqualTo(2);
        assertThat(synced.get("uncategorized")).isEmpty();   // the unlabeled credit isn't asked about

        String month = YearMonth.from(LocalDate.now().minusDays(1)).toString();
        java.util.function.Supplier<JsonNode> totals = () -> {
            try { return ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", month)).get("totals"); }
            catch (Exception e) { throw new RuntimeException(e); }
        };
        java.util.function.Supplier<Double> sum = () -> {
            double total = 0;
            for (var f : (Iterable<Map.Entry<String, JsonNode>>) totals.get()::fields) total += f.getValue().asDouble();
            return total;
        };
        assertThat(sum.get()).isEqualTo(30.0);

        // moved to a category with nothing else bought: that month shows $0 there (never below), the
        // purchase counts in full; moved back, it lowers the purchase again (the day kept the -20)
        String refundUrl = "/api/costs/transactions/" + me.name() + "/refund/category?month=" + month;
        ok(putJson(me, refundUrl, Map.of("category", "Gifts & Donations")));
        assertThat(totals.get().path("Gifts & Donations").asDouble()).isZero();
        assertThat(sum.get()).isEqualTo(50.0);
        ok(putJson(me, refundUrl, Map.of("category", "Groceries")));
        assertThat(sum.get()).isEqualTo(30.0);

        // the bank takes the refund back: the full purchase counts again
        when(call.execute()).thenReturn(retrofit2.Response.success(new TransactionsSyncResponse().added(List.of()).modified(List.of())
                .removed(List.of(new com.plaid.client.model.RemovedTransaction().transactionId("refund"))).hasMore(false).nextCursor("c2")));
        assertThat(ok(postJson(me, "/api/plaid/sync", Map.of("username", user))).get("removed").asInt()).isEqualTo(1);
        assertThat(sum.get()).isEqualTo(50.0);
    }

    @Test
    @DisplayName("Quiz: a refund lowers that category's usual spending and shows in the transactions")
    @SuppressWarnings("unchecked")
    void refundsInQuizAverages() throws Exception {
        User me = newUser();
        tokenStore.saveAccessToken(me.name().toLowerCase(), "item-1", "access-test");
        List<Transaction> all = List.of(
                credit("buy", "TARGET", 100.0, "GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_SUPERSTORES"),
                credit("refund", "TARGET", -30.0, "GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_SUPERSTORES"),
                credit("pay", "ACME PAYROLL", -1000.0, "INCOME", "INCOME_WAGES"),
                credit("mystery", "CREDIT 0042", -15.0, null, null));
        retrofit2.Call<com.plaid.client.model.TransactionsGetResponse> getCall = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(getCall.execute()).thenAnswer(x -> retrofit2.Response.success(
                new com.plaid.client.model.TransactionsGetResponse().totalTransactions(all.size()).transactions(all)));
        when(plaidApi.transactionsGet(any())).thenReturn(getCall);

        JsonNode summary = ok(getAs(me, "/api/plaid/spending-summary/{u}", me.name()));
        double usual = 0;
        for (var f : (Iterable<Map.Entry<String, JsonNode>>) summary.get("averages")::fields) usual += f.getValue().asDouble();
        assertThat(usual).isEqualTo(70.0);
        assertThat(summary.get("transactions").toString()).contains("-30.0").doesNotContain("ACME").doesNotContain("CREDIT 0042");
    }

    @Test
    @DisplayName("Refunds an older version marked handled without recording come in once (catch-up); one deleted later doesn't come back")
    @SuppressWarnings("unchecked")
    void refundCatchUp() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        tokenStore.saveAccessToken(user, "item-1", "access-test");
        Transaction buy = credit("buy", "TARGET", 50.0, "GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_SUPERSTORES");
        Transaction r1 = credit("r1", "OLD NAVY", -15.0, "GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_CLOTHING_AND_ACCESSORIES");
        Transaction r2 = credit("r2", "OLD NAVY", -10.0, "GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_CLOTHING_AND_ACCESSORIES");
        // what the older version did with them: marked handled, never recorded (the cursor is past them)
        plaidCursorStore.markSeenTxn(user, "item-1", "r1");
        plaidCursorStore.markSeenTxn(user, "item-1", "r2");
        retrofit2.Call<TransactionsSyncResponse> sync = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(sync.execute()).thenReturn(retrofit2.Response.success(new TransactionsSyncResponse()
                .added(List.of(buy)).modified(List.of()).removed(List.of()).hasMore(false).nextCursor("c1")));
        when(plaidApi.transactionsSync(any())).thenReturn(sync);
        List<Transaction> history = List.of(buy, r1, r2);
        retrofit2.Call<com.plaid.client.model.TransactionsGetResponse> get = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(get.execute()).thenAnswer(x -> retrofit2.Response.success(
                new com.plaid.client.model.TransactionsGetResponse().totalTransactions(history.size()).transactions(history)));
        when(plaidApi.transactionsGet(any())).thenReturn(get);

        assertThat(ok(postJson(me, "/api/plaid/sync", Map.of("username", user))).get("added").asInt()).isEqualTo(3); // the trip and both refunds
        String month = YearMonth.from(LocalDate.now().minusDays(1)).toString();
        String txns = ok(getAs(me, "/api/costs/transactions/{u}", me.name()).param("month", month)).toString();
        assertThat(txns).contains("\"r1\"").contains("\"r2\"");

        // deleted by hand: the next sync and the quiz's import don't bring it back
        ok(deleteAs(me, "/api/costs/transactions/{u}/{id}", me.name(), "r2").param("month", month));
        when(sync.execute()).thenReturn(retrofit2.Response.success(new TransactionsSyncResponse()
                .added(List.of()).modified(List.of()).removed(List.of()).hasMore(false).nextCursor("c2")));
        assertThat(ok(postJson(me, "/api/plaid/sync", Map.of("username", user))).get("added").asInt()).isZero();
        assertThat(ok(postJson(me, "/api/plaid/import-history", Map.of("username", user))).get("added").asInt()).isZero();
    }

    @Test
    @DisplayName("Quiz edits on save: removed ones stay out of Monthly Costs (or come out), moved ones go where they were put and stay")
    @SuppressWarnings("unchecked")
    void quizEdits() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        tokenStore.saveAccessToken(user, "item-1", "access-test");
        Transaction tv = credit("tv", "BEST BUY", 900.0, "GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_ELECTRONICS");
        Transaction gift = credit("gift", "TARGET", 60.0, "GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_SUPERSTORES");
        Transaction dinner = credit("dinner", "OLIVE GARDEN", 80.0, "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT");
        Transaction lunch = credit("lunch", "PANERA", 15.0, "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT");
        // the TV and dinner were synced already; the others weren't
        retrofit2.Call<TransactionsSyncResponse> sync = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(sync.execute()).thenReturn(retrofit2.Response.success(new TransactionsSyncResponse()
                .added(List.of(tv, dinner)).modified(List.of()).removed(List.of()).hasMore(false).nextCursor("c1")));
        when(plaidApi.transactionsSync(any())).thenReturn(sync);
        List<Transaction> history = List.of(tv, gift, dinner, lunch);
        retrofit2.Call<com.plaid.client.model.TransactionsGetResponse> get = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(get.execute()).thenAnswer(x -> retrofit2.Response.success(
                new com.plaid.client.model.TransactionsGetResponse().totalTransactions(history.size()).transactions(history)));
        when(plaidApi.transactionsGet(any())).thenReturn(get);
        ok(postJson(me, "/api/plaid/sync", Map.of("username", user)));

        // the quiz shows each one's id, so edits can refer to it
        assertThat(ok(getAs(me, "/api/plaid/spending-summary/{u}", me.name())).get("transactions").toString()).contains("\"id\":\"tv\"");

        JsonNode result = ok(postJson(me, "/api/plaid/import-history", Map.of("username", user,
                "edits", Map.of("tv", "", "gift", "", "dinner", "Date Night", "lunch", "Work Lunches"))));
        assertThat(result.get("edited").asInt()).isEqualTo(2);    // the TV taken out, dinner moved
        assertThat(result.get("added").asInt()).isEqualTo(1);     // lunch, in its new category; the gift left out
        String month = YearMonth.from(LocalDate.now().minusDays(1)).toString();
        JsonNode totals = ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", month)).get("totals");
        assertThat(totals.get("Date Night").asDouble()).isEqualTo(80.0);
        assertThat(totals.get("Work Lunches").asDouble()).isEqualTo(15.0);
        double total = 0;
        for (var f : (Iterable<Map.Entry<String, JsonNode>>) totals::fields) total += f.getValue().asDouble();
        assertThat(total).isEqualTo(95.0);                          // no TV, no gift

        // a later budget change doesn't move what they put by hand
        ok(postJson(me, "/api/budget", Map.of("username", me.name(), "type", "weekly", "budget", Map.of("Eating Out", 50.0, "Shopping", 40.0))));
        totals = ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", month)).get("totals");
        assertThat(totals.get("Date Night").asDouble()).isEqualTo(80.0);
        assertThat(totals.get("Work Lunches").asDouble()).isEqualTo(15.0);
    }
}
