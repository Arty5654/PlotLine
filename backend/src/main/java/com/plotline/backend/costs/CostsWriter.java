package com.plotline.backend.costs;

import com.plotline.backend.service.CostsService;
import org.springframework.stereotype.Component;

import java.util.Map;

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
        costsService.mergeDated(username, type, yyyyMmDd, costs);
    }

    /**
     * Add costs to a single day (ADD logic).
     * Used by manual assignment to add transactions to existing totals.
     */
    public void addDated(String username, String type, String yyyyMmDd, Map<String, Double> costs) {
        costsService.addDated(username, type, yyyyMmDd, costs);
    }
}
