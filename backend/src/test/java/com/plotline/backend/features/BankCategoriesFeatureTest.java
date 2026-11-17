package com.plotline.backend.features;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import com.fasterxml.jackson.databind.JsonNode;
import com.plaid.client.model.PersonalFinanceCategory;
import com.plaid.client.model.Transaction;
import com.plaid.client.model.TransactionsGetResponse;
import com.plotline.backend.categorize.Categorizer;
import com.plotline.backend.plaid.TokenStore;

/** Sorting bank transactions: more categories than before, the user's own names, and AI for the unlabeled. */
class BankCategoriesFeatureTest extends FeatureTestBase {

    @Autowired TokenStore tokenStore;
    @Autowired Categorizer categorizer;

    private static Transaction txn(String merchant, String primary, String detailed, double amount, int daysAgo) {
        Transaction t = new Transaction().merchantName(merchant).name(merchant).amount(amount).pending(false)
                .date(LocalDate.now().minusDays(daysAgo));
        if (primary != null) t.personalFinanceCategory(new PersonalFinanceCategory().primary(primary).detailed(detailed));
        return t;
    }

    @SuppressWarnings("unchecked")
    private void bankReturns(List<Transaction> transactions) throws Exception {
        retrofit2.Call<TransactionsGetResponse> call = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(call.execute()).thenAnswer(i -> retrofit2.Response.success(
                new TransactionsGetResponse().totalTransactions(transactions.size()).transactions(transactions)));
        when(plaidApi.transactionsGet(any())).thenReturn(call);
    }

    @Test
    @DisplayName("Insurance, taxes, home, car repairs and more get their own categories; the AI sorts the unlabeled once")
    void moreCategories() throws Exception {
        User me = newUser();
        tokenStore.saveAccessToken(me.name().toLowerCase(), "item-1", "access-test");
        bankReturns(List.of(
                txn("GEICO", "GENERAL_SERVICES", "GENERAL_SERVICES_INSURANCE", 600, 60),
                txn("LEMONADE", "GENERAL_SERVICES", "GENERAL_SERVICES_INSURANCE", 15, 30),
                txn("VA DMV", "GOVERNMENT_AND_NON_PROFIT", "GOVERNMENT_AND_NON_PROFIT_GOVERNMENT_DEPARTMENTS_AND_AGENCIES", 45, 20),
                txn("IKEA", "HOME_IMPROVEMENT", "HOME_IMPROVEMENT_FURNITURE", 300, 10),
                txn("JIFFY LUBE", "GENERAL_SERVICES", "GENERAL_SERVICES_AUTOMOTIVE", 90, 5),
                txn("BANFIELD PET HOSPITAL", "MEDICAL", "MEDICAL_VETERINARY_SERVICES", 120, 15),
                txn("VERIZON", "RENT_AND_UTILITIES", "RENT_AND_UTILITIES_TELEPHONE", 70, 12),
                txn("BLUE BOTTLE HOLDINGS", null, null, 12, 3),          // the bank couldn't label it
                txn("ZELLE TO A FRIEND", "TRANSFER_OUT", "TRANSFER_OUT_ACCOUNT_TRANSFER", 500, 2)));
        when(openAIService.estimateJson(anyString(), anyString(), anyInt()))
                .thenReturn("{\"categories\": {\"BLUE BOTTLE HOLDINGS\": \"Eating Out\"}}");

        JsonNode averages = ok(getAs(me, "/api/plaid/spending-summary/{u}", me.name())).get("averages");
        assertThat(averages.has("Car Insurance")).isTrue();       // GEICO: an insurer the app knows is for cars
        assertThat(averages.has("Insurance")).isTrue();           // renters insurance
        assertThat(averages.has("Taxes & Fees")).isTrue();
        assertThat(averages.has("Home")).isTrue();
        assertThat(averages.has("Car Maintenance")).isTrue();
        assertThat(averages.has("Pet Care")).isTrue();
        assertThat(averages.has("Phone")).isTrue();
        assertThat(averages.has("Eating Out")).isTrue();          // what the AI said
        assertThat(averages.has("Miscellaneous")).isFalse();      // nothing left over (the transfer isn't spending)

        // each transaction and how it was sorted, newest first; the transfer isn't listed
        JsonNode txns = ok(getAs(me, "/api/plaid/spending-summary/{u}", me.name())).get("transactions");
        assertThat(txns.size()).isEqualTo(8);
        assertThat(txns.get(0).get("name").asText()).isEqualTo("BLUE BOTTLE HOLDINGS");
        assertThat(txns.get(0).get("how").asText()).isEqualTo("ai");
        assertThat(txns.get(0).get("category").asText()).isEqualTo("Eating Out");
        java.util.Map<String, String> how = new java.util.HashMap<>();
        txns.forEach(t -> how.put(t.get("name").asText(), t.get("how").asText() + ":" + t.get("category").asText()));
        assertThat(how).containsEntry("GEICO", "store:Car Insurance").containsEntry("IKEA", "bank:Home").doesNotContainKey("ZELLE TO A FRIEND");

        // only the unlabeled merchant was asked about, never the transfer; the answer is remembered
        verify(openAIService, times(1)).estimateJson(anyString(), contains("BLUE BOTTLE HOLDINGS"), anyInt());
        verify(openAIService, never()).estimateJson(anyString(), contains("ZELLE"), anyInt());
        verify(openAIService, times(1)).estimateJson(anyString(), anyString(), anyInt()); // asked once over two summaries
    }

    @Test
    @DisplayName("With a budget, transactions go to the user's own categories: the exact name first, a phone bill to Utilities when there's no Phone")
    void ownCategories() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        ok(postJson(me, "/api/budget", Map.of("username", me.name(), "type", "weekly",
                "budget", Map.of("Utilities", 50.0, "Car Insurance", 25.0, "Health Insurance", 0.0, "Coffee", 10.0, "Taxes & Fees", 5.0))));
        categorizer.clearCategoryCache(user);

        assertThat(categorizer.map(user, txn("VERIZON", "RENT_AND_UTILITIES", "RENT_AND_UTILITIES_TELEPHONE", 70, 1))).isEqualTo("Utilities");
        assertThat(categorizer.map(user, txn("GEICO", "GENERAL_SERVICES", "GENERAL_SERVICES_INSURANCE", 100, 1))).isEqualTo("Car Insurance");
        assertThat(categorizer.map(user, txn("VA DMV", "GOVERNMENT_AND_NON_PROFIT", "GOVERNMENT_AND_NON_PROFIT_TAX_PAYMENT", 40, 1)))
                .isEqualTo("Taxes & Fees");                       // not "Coffee" (which contains "fee")
    }

    @Test
    @DisplayName("Saving the reviewed quiz budget writes the copy the weekly recap, goals and bank sorting read")
    void saveWritesEditedCopy() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/llm/budget/save", Map.of("username", me.name(), "budget", Map.of("Rent", 1000, "Groceries", 400),
                "answers", Map.of("monthlyNet", 4000))));
        JsonNode weekly = bytes("users/" + me.name().toLowerCase() + "/weekly-budget-edited.json");
        assertThat(weekly.get("budget").get("Rent").asDouble()).isEqualTo(250.0);
        assertThat(weekly.get("type").asText()).isEqualTo("weekly");
    }

    private void budget(User me, Map<String, Object> categories) throws Exception {
        ok(postJson(me, "/api/budget", Map.of("username", me.name(), "type", "weekly", "budget", categories)));
        categorizer.clearCategoryCache(me.name().toLowerCase());
    }

    private static Transaction withId(Transaction t, String id) {
        return t.transactionId(id).accountId("acct");
    }

    @Test
    @DisplayName("Narrower categories they have get their transactions (bars out of Eating Out); the rest stays broad")
    void niches() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        budget(me, Map.of("Eating Out", 50.0, "Alcohol & Bars", 20.0, "Coffee", 10.0, "Transportation", 20.0, "Parking", 10.0,
                "Shopping", 30.0, "Clothing", 20.0, "Utilities", 50.0, "Internet", 15.0));
        java.util.function.BiFunction<String, String[], String> sorted = (merchant, label) ->
                categorizer.map(user, txn(merchant, label[0], label[1], 20, 1));
        String[] restaurant = {"FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT"};
        assertThat(sorted.apply("JOE'S TAVERN", restaurant)).isEqualTo("Alcohol & Bars");                 // by the name
        assertThat(sorted.apply("TOTAL WINE", new String[]{"FOOD_AND_DRINK", "FOOD_AND_DRINK_BEER_WINE_AND_LIQUOR"})).isEqualTo("Alcohol & Bars"); // the bank's label
        assertThat(sorted.apply("OLIVE GARDEN", restaurant)).isEqualTo("Eating Out");
        assertThat(sorted.apply("SUSHI BAR KAN", restaurant)).isEqualTo("Eating Out");
        assertThat(sorted.apply("CHIPOTLE", new String[]{"FOOD_AND_DRINK", "FOOD_AND_DRINK_FAST_FOOD"})).isEqualTo("Eating Out"); // no Fast Food
        assertThat(sorted.apply("THE COFFEE BAR", new String[]{"FOOD_AND_DRINK", "FOOD_AND_DRINK_COFFEE"})).isEqualTo("Coffee"); // the label decides
        assertThat(sorted.apply("BAR HARBOR INN", new String[]{"TRAVEL", "TRAVEL_LODGING"})).isEqualTo("Travel");                // a hotel, not a bar
        assertThat(sorted.apply("SPOTHERO", new String[]{"TRANSPORTATION", "TRANSPORTATION_PARKING"})).isEqualTo("Parking");
        assertThat(sorted.apply("LYFT", new String[]{"TRANSPORTATION", "TRANSPORTATION_TAXIS_AND_RIDE_SHARES"})).isEqualTo("Transportation");
        assertThat(sorted.apply("OLD NAVY", new String[]{"GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_CLOTHING_AND_ACCESSORIES"})).isEqualTo("Clothing");
        assertThat(sorted.apply("AMAZON", new String[]{"GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_ONLINE_MARKETPLACES"})).isEqualTo("Shopping");
        assertThat(sorted.apply("COMCAST", new String[]{"RENT_AND_UTILITIES", "RENT_AND_UTILITIES_INTERNET_AND_CABLE"})).isEqualTo("Internet");
        assertThat(sorted.apply("DOMINION ENERGY", new String[]{"RENT_AND_UTILITIES", "RENT_AND_UTILITIES_GAS_AND_ELECTRICITY"})).isEqualTo("Utilities");

        // a name that says the broad one is the broad one, and a narrower one doesn't take all of its group
        User other = newUser();
        budget(other, Map.of("Eating Out & Drinks", 80.0, "Clothing", 20.0));
        String otherUser = other.name().toLowerCase();
        assertThat(categorizer.map(otherUser, txn("JOE'S TAVERN", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 20, 1))).isEqualTo("Eating Out & Drinks");
        assertThat(categorizer.map(otherUser, txn("OLIVE GARDEN", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 20, 1))).isEqualTo("Eating Out & Drinks");
        assertThat(categorizer.map(otherUser, txn("AMAZON", "GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_ONLINE_MARKETPLACES", 20, 1))).isEqualTo("Shopping");
    }

    @Test
    @DisplayName("Their own categories (Golf): the AI says which merchants belong; savings lines aren't asked about; asked again when they change")
    void ownCategoriesByAI() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        budget(me, Map.of("Golf", 40.0, "Eating Out", 50.0, "Savings", 100.0, "Emergency Fund", 50.0, "Car Payment", 300.0));
        List<Transaction> bought = List.of(
                txn("TOPGOLF", "ENTERTAINMENT", "ENTERTAINMENT_SPORTING_EVENTS_AMUSEMENT_PARKS_AND_MUSEUMS", 60, 3),
                txn("GOLF GALAXY", "GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_SPORTING_GOODS", 90, 5),
                txn("OLIVE GARDEN", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 40, 2));
        when(openAIService.estimateJson(contains("of their own"), anyString(), anyInt()))
                .thenReturn("{\"categories\": {\"TOPGOLF\": \"Golf\", \"GOLF GALAXY\": \"golf\", \"OLIVE GARDEN\": \"none\"}}");
        categorizer.prepare(user, bought);

        assertThat(categorizer.map(user, bought.get(0))).isEqualTo("Golf");
        assertThat(categorizer.map(user, bought.get(1))).isEqualTo("Golf");
        assertThat(categorizer.map(user, bought.get(2))).isEqualTo("Eating Out");
        verify(openAIService, times(1)).estimateJson(contains("of their own: Golf."), anyString(), anyInt()); // not Savings, Emergency Fund, Car Payment

        categorizer.prepare(user, bought);                     // already known: not asked again
        verify(openAIService, times(1)).estimateJson(contains("of their own"), anyString(), anyInt());
        budget(me, Map.of("Golf", 40.0, "Date Night", 60.0, "Eating Out", 50.0));
        categorizer.prepare(user, bought);                     // their categories changed: asked again
        verify(openAIService, times(1)).estimateJson(contains("of their own: Date Night, Golf."), anyString(), anyInt());
    }

    @Test
    @DisplayName("Quiz: each transaction says which narrower categories it would move to")
    void quizNiches() throws Exception {
        User me = newUser();
        tokenStore.saveAccessToken(me.name().toLowerCase(), "item-1", "access-test");
        bankReturns(List.of(
                txn("JOE'S TAVERN", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 30, 3),
                txn("OLIVE GARDEN", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 50, 4),
                txn("STARBUCKS", "FOOD_AND_DRINK", "FOOD_AND_DRINK_COFFEE", 6, 5)));
        Map<String, JsonNode> byName = new java.util.HashMap<>();
        ok(getAs(me, "/api/plaid/spending-summary/{u}", me.name())).get("transactions").forEach(t -> byName.put(t.get("name").asText(), t));
        assertThat(byName.get("JOE'S TAVERN").get("category").asText()).isEqualTo("Eating Out");
        assertThat(byName.get("JOE'S TAVERN").get("niches").toString()).isEqualTo("[\"Alcohol & Bars\"]");
        assertThat(byName.get("STARBUCKS").get("niches").toString()).isEqualTo("[\"Coffee\"]");
        assertThat(byName.get("OLIVE GARDEN").has("niches")).isFalse();
    }

    @Test
    @DisplayName("Adding categories sorts recent bank transactions again; hand-moved ones stay; a new fixed cost's are taken out")
    @SuppressWarnings("unchecked")
    void resortAfterBudgetChange() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        tokenStore.saveAccessToken(user, "item-1", "access-test");
        budget(me, Map.of("Eating Out", 50.0, "Groceries", 100.0, "Utilities", 60.0));
        List<Transaction> bank = List.of(
                withId(txn("JOE'S TAVERN", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 30, 1), "tavern"),
                withId(txn("THE PUB", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 25, 1), "pub"),
                withId(txn("OLIVE GARDEN", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 50, 1), "olive"),
                withId(txn("COMCAST", "RENT_AND_UTILITIES", "RENT_AND_UTILITIES_INTERNET_AND_CABLE", 80, 1), "comcast"));
        retrofit2.Call<com.plaid.client.model.TransactionsSyncResponse> sync = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(sync.execute()).thenReturn(retrofit2.Response.success(new com.plaid.client.model.TransactionsSyncResponse()
                .added(bank).modified(List.of()).removed(List.of()).hasMore(false).nextCursor("c1")));
        when(plaidApi.transactionsSync(any())).thenReturn(sync);
        bankReturns(bank);
        ok(postJson(me, "/api/plaid/sync", Map.of("username", user)));
        String month = java.time.YearMonth.from(LocalDate.now().minusDays(1)).toString();
        ok(putJson(me, "/api/costs/transactions/" + me.name() + "/pub/category?month=" + month, Map.of("category", "Groceries"))); // by hand

        ok(postJson(me, "/api/costs/fixed/" + me.name(), Map.of("category", "Internet", "amount", 80)));
        budget(me, Map.of("Eating Out", 50.0, "Groceries", 100.0, "Utilities", 60.0, "Alcohol & Bars", 40.0, "Internet", 80.0));

        JsonNode totals = ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", month)).get("totals");
        assertThat(totals.get("Alcohol & Bars").asDouble()).isEqualTo(30.0);  // the tavern moved
        assertThat(totals.get("Eating Out").asDouble()).isEqualTo(50.0);
        assertThat(totals.get("Groceries").asDouble()).isEqualTo(25.0);       // the pub stays where they put it
        assertThat(totals.get("Internet").asDouble()).isEqualTo(80.0);        // the fixed cost, counted once
        assertThat(totals.path("Utilities").asDouble()).isZero();             // the Comcast bill came out of Utilities
        String txns = ok(getAs(me, "/api/costs/transactions/{u}", me.name()).param("month", month)).toString();
        assertThat(txns).doesNotContain("comcast");

        // only amounts changed: nothing sorted again
        org.mockito.Mockito.clearInvocations(plaidApi);
        budget(me, Map.of("Eating Out", 70.0, "Groceries", 100.0, "Utilities", 60.0, "Alcohol & Bars", 40.0, "Internet", 80.0));
        verify(plaidApi, never()).transactionsGet(any());
    }

    @Test
    @DisplayName("A narrower category inside a fixed cost doesn't count a charge twice (Netflix with Subscriptions fixed)")
    @SuppressWarnings("unchecked")
    void nicheInsideFixed() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        tokenStore.saveAccessToken(user, "item-1", "access-test");
        budget(me, Map.of("Subscriptions", 30.0, "Streaming Services", 20.0, "Music", 15.0, "Shopping", 50.0));
        ok(postJson(me, "/api/costs/fixed/" + me.name(), Map.of("category", "Subscriptions", "amount", 30)));
        retrofit2.Call<com.plaid.client.model.TransactionsSyncResponse> sync = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(sync.execute()).thenReturn(retrofit2.Response.success(new com.plaid.client.model.TransactionsSyncResponse().added(List.of(
                withId(txn("NETFLIX.COM", "ENTERTAINMENT", "ENTERTAINMENT_TV_AND_MOVIES", 15.49, 1), "netflix"),
                withId(txn("GUITAR CENTER", "GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_OTHER_GENERAL_MERCHANDISE", 60, 1), "guitar")))
                .modified(List.of()).removed(List.of()).hasMore(false).nextCursor("c1")));
        when(plaidApi.transactionsSync(any())).thenReturn(sync);
        JsonNode result = ok(postJson(me, "/api/plaid/sync", Map.of("username", user)));
        assertThat(result.get("skippedFixed").asInt()).isEqualTo(1);  // Netflix: in the Subscriptions fixed cost already
        assertThat(result.get("added").asInt()).isEqualTo(1);
        JsonNode totals = ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month",
                java.time.YearMonth.from(LocalDate.now().minusDays(1)).toString())).get("totals");
        assertThat(totals.get("Music").asDouble()).isEqualTo(60.0);
        assertThat(totals.path("Streaming Services").asDouble()).isZero();
    }

    @Test
    @DisplayName("The AI picks the narrower category when the label and name don't (a bar without \"bar\" in its name)")
    void nicheByAI() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        budget(me, Map.of("Eating Out", 100.0, "Alcohol & Bars", 40.0));
        List<Transaction> bought = List.of(
                txn("THE BRASS TAP", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 45, 2),
                txn("OLIVE GARDEN", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 60, 3),
                txn("JOE'S TAVERN", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 30, 4));
        when(openAIService.estimateJson(contains("narrower budget categories"), anyString(), anyInt()))
                .thenReturn("{\"categories\": {\"THE BRASS TAP\": \"Alcohol & Bars\", \"OLIVE GARDEN\": \"none\"}}");
        categorizer.prepare(user, bought);

        assertThat(categorizer.map(user, bought.get(0))).isEqualTo("Alcohol & Bars");
        assertThat(categorizer.map(user, bought.get(1))).isEqualTo("Eating Out");
        assertThat(categorizer.map(user, bought.get(2))).isEqualTo("Alcohol & Bars");                 // by its name, not asked
        verify(openAIService, never()).estimateJson(anyString(), contains("TAVERN"), anyInt());
        verify(openAIService, times(1)).estimateJson(contains("Alcohol & Bars = bars, pubs"), contains("THE BRASS TAP -> "), anyInt());
        categorizer.prepare(user, bought);                                                            // remembered
        verify(openAIService, times(1)).estimateJson(contains("narrower budget categories"), anyString(), anyInt());
    }

    @Test
    @DisplayName("\"Always put this place in…\": past transactions from it move (hand-moved ones too) and new ones follow")
    @SuppressWarnings("unchecked")
    void placeRule() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        tokenStore.saveAccessToken(user, "item-1", "access-test");
        budget(me, Map.of("Eating Out", 100.0, "Groceries", 100.0, "Alcohol & Bars", 40.0));
        retrofit2.Call<com.plaid.client.model.TransactionsSyncResponse> sync = org.mockito.Mockito.mock(retrofit2.Call.class);
        when(sync.execute()).thenReturn(retrofit2.Response.success(new com.plaid.client.model.TransactionsSyncResponse().added(List.of(
                withId(txn("MCGINTY'S", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 30, 1), "m1"),
                withId(txn("MCGINTY'S", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 20, 1), "m2"),
                withId(txn("OLIVE GARDEN", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 50, 1), "o1")))
                .modified(List.of()).removed(List.of()).hasMore(false).nextCursor("c1")));
        when(plaidApi.transactionsSync(any())).thenReturn(sync);
        ok(postJson(me, "/api/plaid/sync", Map.of("username", user)));
        String month = java.time.YearMonth.from(LocalDate.now().minusDays(1)).toString();
        ok(putJson(me, "/api/costs/transactions/" + me.name() + "/m2/category?month=" + month, Map.of("category", "Groceries")));

        JsonNode moved = ok(postJson(me, "/api/category/place", Map.of("username", me.name(), "merchant", "McGinty's", "category", "Alcohol & Bars")));
        assertThat(moved.get("moved").asInt()).isEqualTo(2);
        JsonNode totals = ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", month)).get("totals");
        assertThat(totals.get("Alcohol & Bars").asDouble()).isEqualTo(50.0);
        assertThat(totals.get("Eating Out").asDouble()).isEqualTo(50.0);
        assertThat(totals.path("Groceries").asDouble()).isZero();

        // from now on too, however the name is spelled when syncing
        assertThat(categorizer.map(me.name(), txn("MCGINTY'S", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 25, 0))).isEqualTo("Alcohol & Bars");
        assertThat(categorizer.map(user, txn("MCGINTY'S", "FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT", 25, 0))).isEqualTo("Alcohol & Bars");
    }
}
