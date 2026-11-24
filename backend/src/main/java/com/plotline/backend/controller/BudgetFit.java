package com.plotline.backend.controller;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * The AI's budget made to fit take-home: if it plans more than they bring home, wants are lowered
 * evenly first, then savings (never below the plan's share). Bills they gave, debt minimums and
 * amounts they typed aren't touched. Also: where they usually spend more than the plan allows.
 * (The same order the review screen's Rebalance uses.)
 */
final class BudgetFit {
    private BudgetFit() { }

    static final Set<String> SAVING = Set.of("savings", "brokerage", "roth ira", "emergency fund", "investments", "investing",
            "401k", "401k contribution", "401(k) contribution", "hsa");
    static final Set<String> NEEDS = Set.of("rent", "mortgage", "utilities", "internet", "phone", "groceries", "transportation",
            "commute", "gas", "car insurance", "car payment", "health insurance", "insurance", "renters insurance", "medical",
            "childcare", "parking", "tolls", "dental", "vision", "pet care", "baby supplies", "education", "car registration",
            "car maintenance", "taxes & fees");

    private static String key(String c) { return c.toLowerCase(Locale.ROOT).strip(); }
    static boolean isSaving(String c) { return SAVING.contains(key(c)) || com.plotline.backend.plan.BudgetLines.isPlanSaving(c); }
    static boolean isNeed(String c) { return NEEDS.contains(key(c)) || key(c).startsWith("debt - "); }

    /** lowers lines so the total fits; returns what each lowered line was. Whole dollars. */
    static Map<String, Double> fit(Map<String, Double> monthly, double takeHome, Set<String> locked, double savingsFloor) {
        Map<String, Double> before = new LinkedHashMap<>();
        double total = monthly.values().stream().mapToDouble(Double::doubleValue).sum();
        if (takeHome <= 0 || total <= takeHome) return before;
        double need = total - takeHome;
        List<String> wants = monthly.keySet().stream().filter(c -> !locked.contains(c) && !isSaving(c) && !isNeed(c)).sorted().toList();
        need -= trim(monthly, wants, need, Double.MAX_VALUE, before);
        List<String> savings = monthly.keySet().stream().filter(c -> !locked.contains(c) && isSaving(c)).sorted().toList();
        double savingsNow = savings.stream().mapToDouble(monthly::get).sum();
        trim(monthly, savings, need, Math.max(0, savingsNow - savingsFloor), before);
        return before;
    }

    private static double trim(Map<String, Double> monthly, List<String> lines, double need, double available, Map<String, Double> before) {
        double pool = lines.stream().mapToDouble(monthly::get).sum();
        if (pool <= 0 || need <= 0 || available <= 0) return 0;
        double target = Math.min(need, Math.min(available, pool));
        double cut = 0;
        for (String line : lines) {
            double amount = monthly.get(line);
            double lowered = Math.max(0, Math.floor(amount - amount / pool * target));
            if (lowered < amount) {
                before.putIfAbsent(line, amount);
                monthly.put(line, lowered);
                cut += amount - lowered;
            }
        }
        return cut;
    }

    record Overspend(String category, double usual, double planned) { }

    /** categories where their real spending is well above the plan (at least 15% and $40 more) */
    static List<Overspend> overspending(Map<String, Double> monthly, Map<String, Object> bankAverages) {
        List<Overspend> out = new ArrayList<>();
        bankAverages.forEach((category, value) -> {
            double usual = QuizDetails.number(value);
            String line = monthly.keySet().stream().filter(c -> c.equalsIgnoreCase(category)).findFirst().orElse(null);
            if (line == null || isSaving(line)) return;
            double planned = monthly.get(line);
            if (usual - planned >= 40 && usual > planned * 1.15) out.add(new Overspend(line, Math.round(usual), planned));
        });
        out.sort(Comparator.comparingDouble((Overspend o) -> o.usual() - o.planned()).reversed());
        return out;
    }
}
