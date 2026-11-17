package com.plotline.backend.controller;

import static com.plotline.backend.util.UsernameUtils.normalize;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import com.plaid.client.model.Transaction;
import com.plaid.client.model.TransactionsGetRequest;
import com.plaid.client.model.TransactionsGetRequestOptions;
import com.plaid.client.model.TransactionsGetResponse;
import com.plaid.client.request.PlaidApi;
import com.plotline.backend.categorize.Categorizer;
import com.plotline.backend.plaid.TokenStore;

/**
 * The budget quiz's "from your bank" amounts: what was spent per month in each standard category
 * over the last ~3 months of linked-bank transactions. Read straight from Plaid; nothing is saved,
 * and nothing is added to spending (that starts when the bank is synced after the budget exists).
 */
@RestController
public class SpendingSummaryController {
    private static final Logger log = LoggerFactory.getLogger(SpendingSummaryController.class);

    static final int DAYS = 90;

    /** money moving between accounts, paying cards and loans, or coming in isn't spending */
    static final Set<String> NOT_SPENDING = Set.of("TRANSFER_IN", "TRANSFER_OUT", "LOAN_PAYMENTS", "INCOME", "BANK_FEES");

    /**
     * Money back for something bought (a return, a refund): a credit the bank labeled as spending, so
     * it lowers that category. Not income, transfers, card or loan payments or bank fees, and not a
     * credit the bank couldn't label (it could be anything, a paycheck included).
     */
    static boolean isRefund(Transaction t) {
        if (Boolean.TRUE.equals(t.getPending()) || t.getAmount() == null || t.getAmount() >= 0) return false;
        String primary = t.getPersonalFinanceCategory() != null ? t.getPersonalFinanceCategory().getPrimary() : null;
        return primary != null && !NOT_SPENDING.contains(primary);
    }

    private final PlaidApi plaid;
    private final TokenStore tokens;
    private final Categorizer categorizer;

    public SpendingSummaryController(PlaidApi plaid, TokenStore tokens, Categorizer categorizer) {
        this.plaid = plaid;
        this.tokens = tokens;
        this.categorizer = categorizer;
    }

    /**
     * {linked, ready, months, averages: {"Groceries": 412, ...}, subscriptionCharges: [...]}.
     * `ready: false` with `linked: true` means the bank is still sending its history (it can take a
     * few minutes after linking). transactions: each one counted, newest first ({date, name, amount,
     * category, how}: how = yours | store | bank | ai | none). subscriptionCharges are the charges counted as Subscriptions (by
     * merchant: {name, amount (the latest), dayOfMonth, lastDate, times}), so the quiz can show what
     * that average is made of even when they don't repeat enough to be detected as subscriptions.
     */
    /**
     * One transaction for the quiz: niches are the narrower categories it would move to if switched on
     * (Alcohol & Bars out of Eating Out), best first; left out when there are none.
     */
    private Map<String, Object> row(String user, Transaction t, String shown, String category, String how) {
        Map<String, Object> row = new LinkedHashMap<>();
        if (t.getTransactionId() != null) row.put("id", t.getTransactionId()); // the quiz's remove/move edits refer to it
        row.put("date", t.getDate() != null ? t.getDate().toString() : "");
        row.put("name", shown == null ? "" : shown);
        row.put("amount", Math.round(t.getAmount() * 100) / 100.0);
        row.put("category", category);
        row.put("how", how);
        List<String> niches = categorizer.nichesFor(user, t);
        if (!niches.isEmpty()) row.put("niches", niches);
        return row;
    }

    @GetMapping("/api/plaid/spending-summary/{username}")
    public Map<String, Object> summary(@PathVariable String username) throws Exception {
        String user = normalize(username);
        Map<String, String> accessTokens = new LinkedHashMap<>(tokens.listAccessTokens(user));
        String tokenOwner = user;
        if (accessTokens.isEmpty()) { accessTokens.putAll(tokens.listAccessTokens(username)); tokenOwner = username; }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("linked", !accessTokens.isEmpty());
        if (accessTokens.isEmpty()) {
            out.put("ready", false);
            return out;
        }

        LocalDate end = LocalDate.now();
        LocalDate start = end.minusDays(DAYS);
        Map<String, Double> totals = new LinkedHashMap<>();
        Map<String, Map<String, Object>> subscriptionCharges = new LinkedHashMap<>();
        LocalDate earliest = end;
        boolean anyReady = false;
        List<Transaction> spending = new ArrayList<>();
        List<Transaction> refunds = new ArrayList<>();

        for (var item : accessTokens.entrySet()) {
            String accessToken = item.getValue();
            // only the accounts they picked (the same ones Monthly Costs syncs)
            List<String> selected = tokens.getSelectedAccounts(tokenOwner, item.getKey());
            int offset = 0;
            while (true) {
                TransactionsGetRequest req = new TransactionsGetRequest().accessToken(accessToken).startDate(start).endDate(end)
                        .options(new TransactionsGetRequestOptions().count(500).offset(offset).includePersonalFinanceCategory(true));
                var response = plaid.transactionsGet(req).execute();
                TransactionsGetResponse body = response.body();
                if (!response.isSuccessful() || body == null) {
                    // most often PRODUCT_NOT_READY right after linking
                    log.info("Spending summary: Plaid not ready for one bank ({})", response.code());
                    break;
                }
                anyReady = true;
                for (Transaction t : body.getTransactions()) {
                    if (selected != null && !selected.isEmpty() && !selected.contains(t.getAccountId())) continue;
                    if (isRefund(t)) { refunds.add(t); continue; }
                    if (Boolean.TRUE.equals(t.getPending()) || t.getAmount() == null || t.getAmount() <= 0) continue;
                    String primary = t.getPersonalFinanceCategory() != null ? t.getPersonalFinanceCategory().getPrimary() : null;
                    if (primary != null && NOT_SPENDING.contains(primary)) continue;
                    spending.add(t);
                }
                offset += body.getTransactions().size();
                if (body.getTransactions().isEmpty() || offset >= body.getTotalTransactions()) break;
            }
        }

        // merchants the bank couldn't label: asked about once (AI), so less lands in Miscellaneous
        if (!spending.isEmpty()) categorizer.prepare(user, spending);
        List<Map<String, Object>> sorted = new ArrayList<>();
        for (Transaction t : spending) {
            Categorizer.Sorted how = categorizer.sortToStandard(user, t);
            String category = how.category();
            if (category == null || category.isBlank() || "Uncategorized".equalsIgnoreCase(category)) category = "Miscellaneous";
            // so they can see each transaction and why it landed where it did
            String shown = t.getMerchantName() != null && !t.getMerchantName().isBlank() ? t.getMerchantName() : t.getName();
            sorted.add(row(user, t, shown, category, how.how()));
            totals.merge(category, t.getAmount(), Double::sum);
            if ("Subscriptions".equals(category) && t.getDate() != null) {
                // the same name the recurring-charge check uses, so the app can tell them apart
                String name = t.getMerchantName() != null && !t.getMerchantName().isBlank() ? t.getMerchantName() : t.getName();
                Map<String, Object> charge = subscriptionCharges.computeIfAbsent(name.toLowerCase(), k -> new LinkedHashMap<>());
                charge.merge("times", 1, (a, b) -> (int) a + (int) b);
                LocalDate last = (LocalDate) charge.get("last");
                if (last == null || t.getDate().isAfter(last)) {
                    charge.put("last", t.getDate());
                    charge.put("name", name);
                    charge.put("amount", Math.round(t.getAmount() * 100) / 100.0);
                }
            }
            if (t.getDate() != null && t.getDate().isBefore(earliest)) earliest = t.getDate();
        }

        // refunds lower the category they came back to (one the bank couldn't place is left out)
        for (Transaction t : refunds) {
            Categorizer.Sorted how = categorizer.sortToStandard(user, t);
            String category = how.category();
            if (category == null || category.isBlank() || "Uncategorized".equalsIgnoreCase(category)) continue;
            String shown = t.getMerchantName() != null && !t.getMerchantName().isBlank() ? t.getMerchantName() : t.getName();
            sorted.add(row(user, t, shown, category, how.how()));
            totals.merge(category, t.getAmount(), Double::sum);
        }

        out.put("ready", anyReady);
        if (!anyReady) return out;
        // a month or more of history; less than that is counted as one month
        double months = Math.max(1, ChronoUnit.DAYS.between(earliest, end) / 30.44);
        months = Math.round(months * 10) / 10.0;
        Map<String, Double> averages = new LinkedHashMap<>();
        double m = months;
        totals.entrySet().stream()
                .filter(e -> e.getValue() > 0) // refunds can outweigh what was bought in the window
                .sorted(Map.Entry.<String, Double>comparingByValue().reversed())
                .forEach(e -> averages.put(e.getKey(), (double) Math.round(e.getValue() / m)));
        out.put("months", months);
        out.put("averages", averages);
        List<Map<String, Object>> charges = new ArrayList<>();
        subscriptionCharges.values().stream()
                .sorted(Comparator.comparing((Map<String, Object> c) -> (LocalDate) c.get("last")).reversed())
                .forEach(c -> {
                    LocalDate last = (LocalDate) c.get("last");
                    charges.add(Map.of("name", c.get("name"), "amount", c.get("amount"), "dayOfMonth", last.getDayOfMonth(),
                            "lastDate", last.toString(), "times", c.get("times")));
                });
        out.put("subscriptionCharges", charges);
        sorted.sort(Comparator.comparing((Map<String, Object> m2) -> (String) m2.get("date")).reversed());
        out.put("transactions", sorted);
        return out;
    }
}
