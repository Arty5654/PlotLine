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
     * Merge a single day into weekly/monthly files (SET logic).
     * Used by sync to set the day's total for each category.
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
     * Store a single transaction detail in the monthly period file.
     */
    public void storeTransaction(String username, String dateStr, String txnId, String name, double amount, String category, String source) {
        Map<String, Object> txn = new LinkedHashMap<>();
        txn.put("id", txnId);
        txn.put("name", name);
        txn.put("amount", Math.round(amount * 100.0) / 100.0);
        txn.put("category", category);
        txn.put("date", dateStr);
        txn.put("source", source);
        costsService.storeTransaction(username, dateStr, txn);
    }
}
