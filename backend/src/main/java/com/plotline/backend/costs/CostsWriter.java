package com.plotline.backend.costs;

import com.plotline.backend.service.CostsService;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.LinkedHashMap;

@Component
public class CostsWriter {

    private final CostsService costsService;

    public CostsWriter(CostsService costsService) {
        this.costsService = costsService;
    }

    /**
     * Merge a single day into weekly/monthly files (SET logic): the day's amount for each category is
     * replaced. Bank transactions use addDated instead, so they don't wipe what the day already has.
     */
    public void mergeDated(String username, String type, String yyyyMmDd, Map<String, Double> costs) {
        costsService.mergeDated(username, type, yyyyMmDd, costs, false);
    }

    /**
     * Add costs to a single day (ADD logic).
     * Used by manual assignment to add transactions to existing totals.
     */
    public void addDated(String username, String type, String yyyyMmDd, Map<String, Double> costs) {
        costsService.addDated(username, type, yyyyMmDd, costs);
    }

    /**
     * A charge the bank took back (reversed, or replaced by a corrected one): out of Monthly Costs if it
     * was recorded, looking through this month and the 3 before (the import goes back 90 days).
     */
    public boolean removeTransaction(String username, String txnId) {
        java.time.YearMonth month = java.time.YearMonth.now();
        for (int i = 0; i < 4; i++, month = month.minusMonths(1)) {
            if (costsService.deleteTransaction(username, month.toString(), txnId)) return true;
        }
        return false;
    }

    /** ids of the transactions already recorded in a month (yyyy-MM), synced or assigned by hand */
    public java.util.Set<String> storedTransactionIds(String username, String month) {
        java.util.Set<String> ids = new java.util.HashSet<>();
        for (var t : costsService.getTransactions(username, month)) if (t.get("id") != null) ids.add(String.valueOf(t.get("id")));
        return ids;
    }

    /**
     * Store a single transaction detail in the monthly period file.
     */
    /** chosen by hand (the quiz's Move): re-sorting after a budget change leaves it where they put it */
    public void storeTransactionChosen(String username, String dateStr, String txnId, String name, double amount, String category) {
        storeTransaction(username, dateStr, txnId, name, amount, category, "plaid", true);
    }

    /** out of Monthly Costs (the quiz's Remove), amount and all */
    public boolean deleteTransaction(String username, String month, String txnId) {
        return costsService.deleteTransaction(username, month, txnId);
    }

    /** to another category, chosen by hand (the quiz's Move) */
    public void moveTransaction(String username, String month, String txnId, String category) {
        costsService.recategorizeTransaction(username, month, txnId, category, true);
    }

    public void storeTransaction(String username, String dateStr, String txnId, String name, double amount, String category, String source) {
        storeTransaction(username, dateStr, txnId, name, amount, category, source, false);
    }

    private void storeTransaction(String username, String dateStr, String txnId, String name, double amount, String category, String source, boolean byHand) {
        Map<String, Object> txn = new LinkedHashMap<>();
        txn.put("id", txnId);
        txn.put("name", name);
        txn.put("amount", Math.round(amount * 100.0) / 100.0);
        txn.put("category", category);
        txn.put("date", dateStr);
        txn.put("source", source);
        if (byHand) txn.put("movedByHand", true);
        costsService.storeTransaction(username, dateStr, txn);
    }
}
