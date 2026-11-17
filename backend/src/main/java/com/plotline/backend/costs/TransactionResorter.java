package com.plotline.backend.costs;

import static com.plotline.backend.util.UsernameUtils.normalize;

import java.io.ByteArrayInputStream;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plaid.client.model.Transaction;
import com.plaid.client.model.TransactionsGetRequest;
import com.plaid.client.model.TransactionsGetRequestOptions;
import com.plaid.client.model.TransactionsGetResponse;
import com.plaid.client.request.PlaidApi;
import com.plotline.backend.categorize.Categorizer;
import com.plotline.backend.plaid.TokenStore;
import com.plotline.backend.service.CostsService;
import com.plotline.backend.service.FixedCosts;
import com.plotline.backend.service.S3Service;

/**
 * When a budget's categories change (Alcohol & Bars added, say), the bank transactions already in
 * Monthly Costs from the last 90 days are sorted again, so past bar tabs move out of Eating Out.
 * Ones they moved, edited or assigned by hand stay where they are; one that now belongs to a fixed
 * cost is taken out (the fixed amount counts it). The categories last sorted with are kept in
 * users/<u>/sorted-categories.json, so nothing happens when only amounts change.
 */
@Component
public class TransactionResorter {
    private static final Logger log = LoggerFactory.getLogger(TransactionResorter.class);
    static final int DAYS = 90;

    private final PlaidApi plaid;
    private final TokenStore tokens;
    private final Categorizer categorizer;
    private final CostsService costs;
    private final FixedCosts fixedCosts;
    private final S3Service s3;
    private final ObjectMapper json = new ObjectMapper();

    public TransactionResorter(PlaidApi plaid, TokenStore tokens, Categorizer categorizer, CostsService costs,
                               FixedCosts fixedCosts, S3Service s3) {
        this.plaid = plaid;
        this.tokens = tokens;
        this.categorizer = categorizer;
        this.costs = costs;
        this.fixedCosts = fixedCosts;
        this.s3 = s3;
    }

    private static String key(String user) {
        return "users/" + user + "/sorted-categories.json";
    }

    /** after a budget is saved: sorts again if its categories changed; how many transactions moved */
    public int afterBudgetChange(String username) {
        String user = normalize(username);
        try {
            categorizer.clearCategoryCache(user);
            List<String> now = new ArrayList<>(new TreeSet<>(categorizer.budgetCategories(user)));
            if (now.equals(lastSorted(user))) return 0;
            int moved = resort(username);
            byte[] bytes = json.writeValueAsBytes(now);
            s3.uploadFile(key(user), new ByteArrayInputStream(bytes), bytes.length);
            return moved;
        } catch (Exception e) {
            log.warn("Sorting transactions again after a budget change failed: {}", e.getMessage());
            return 0;
        }
    }

    private List<String> lastSorted(String user) {
        try {
            return json.readValue(s3.downloadFile(key(user)), new TypeReference<List<String>>() { });
        } catch (Exception e) {
            return null; // never sorted with this budget
        }
    }

    /**
     * "Always put this place in…": its transactions from the last 90 days in Monthly Costs move there
     * (ones moved by hand too: the rule is the newer choice; edited amounts stay). Into a fixed cost,
     * they come out (the fixed amount counts them). Returns how many changed.
     */
    public int applyPlaceRule(String username, String merchant, String category) {
        String user = normalize(username);
        String place = merchant.strip().toUpperCase();
        Set<String> fixed = fixedCosts.categories(user);
        int changed = 0;
        YearMonth end = YearMonth.now();
        for (YearMonth month = end.minusMonths(3); !month.isAfter(end); month = month.plusMonths(1)) {
            for (Map<String, Object> stored : List.copyOf(costs.getTransactions(user, month.toString()))) {
                Object name = stored.get("name");
                if (name == null || !String.valueOf(name).strip().toUpperCase().equals(place)) continue;
                if (!"plaid".equals(stored.get("source")) && !"manual".equals(stored.get("source"))) continue;
                if (category.equalsIgnoreCase(String.valueOf(stored.get("category")))) continue;
                String id = String.valueOf(stored.get("id"));
                if (fixed.contains(category.toLowerCase())) costs.deleteTransaction(user, month.toString(), id);
                else costs.recategorizeTransaction(user, month.toString(), id, category);
                changed++;
            }
        }
        return changed;
    }

    /** sorts the recorded bank transactions of the last 90 days into the budget's current categories */
    int resort(String username) throws Exception {
        String user = normalize(username);
        Map<String, String> items = new LinkedHashMap<>(tokens.listAccessTokens(user));
        if (items.isEmpty()) items.putAll(tokens.listAccessTokens(username));
        if (items.isEmpty()) return 0;

        // what the bank says about each (its labels and names decide the category)
        LocalDate end = LocalDate.now(), start = end.minusDays(DAYS);
        Map<String, Transaction> byId = new LinkedHashMap<>();
        for (String accessToken : items.values()) {
            int offset = 0;
            while (true) {
                var response = plaid.transactionsGet(new TransactionsGetRequest().accessToken(accessToken).startDate(start).endDate(end)
                        .options(new TransactionsGetRequestOptions().count(500).offset(offset).includePersonalFinanceCategory(true))).execute();
                TransactionsGetResponse page = response.body();
                if (!response.isSuccessful() || page == null) break;
                for (Transaction t : page.getTransactions()) if (t.getTransactionId() != null) byId.put(t.getTransactionId(), t);
                offset += page.getTransactions().size();
                if (page.getTransactions().isEmpty() || offset >= page.getTotalTransactions()) break;
            }
        }
        if (byId.isEmpty()) return 0;
        categorizer.prepare(user, byId.values());
        Set<String> fixed = fixedCosts.categories(user);

        int moved = 0;
        YearMonth month = YearMonth.from(start);
        for (; !month.isAfter(YearMonth.from(end)); month = month.plusMonths(1)) {
            for (Map<String, Object> stored : List.copyOf(costs.getTransactions(user, month.toString()))) {
                if (!"plaid".equals(stored.get("source")) || Boolean.TRUE.equals(stored.get("movedByHand"))
                        || stored.containsKey("originalAmount")) continue;
                Transaction t = byId.get(String.valueOf(stored.get("id")));
                if (t == null) continue;
                String now = categorizer.map(user, t);
                if (now == null || now.isBlank() || "Uncategorized".equalsIgnoreCase(now)) continue; // keeps where it is
                if (now.equalsIgnoreCase(String.valueOf(stored.get("category")))) continue;
                String id = String.valueOf(stored.get("id"));
                String broad = categorizer.mapBroad(user, t);
                if (fixed.contains(now.toLowerCase()) || (broad != null && fixed.contains(broad.toLowerCase()))) {
                    costs.deleteTransaction(user, month.toString(), id); // a fixed cost counts it already
                } else {
                    costs.recategorizeTransaction(user, month.toString(), id, now);
                }
                moved++;
            }
        }
        log.info("Sorted bank transactions again for a budget change: {} moved", moved);
        return moved;
    }
}
