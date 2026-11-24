package com.plotline.backend.controller;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import com.plotline.backend.plan.BudgetLines;

/**
 * The quiz budget's Savings, split by what it's for (from the Plan tab):
 *   1. goals with a target date get what they need each month, from up to half of it while the
 *      emergency fund isn't full (all of it once it is), nearest date first
 *   2. the emergency fund gets the rest, up to what it still needs
 *   3. goals still short get more if anything is left
 *   4. what's left stays in Savings
 * A goal without a date keeps what the budget already gives it (set in Plan), like a dated goal's
 * need. Lines they typed on the review screen stay as typed. Each line gets a "why".
 */
final class SavingsSplit {
    private SavingsSplit() { }

    /** `kept`: no date; its need is what the budget already gives it */
    record Goal(String name, double target, double saved, LocalDate date, double monthlyNeeded, boolean kept) { }

    private static final DateTimeFormatter MONTH = DateTimeFormatter.ofPattern("MMM yyyy", Locale.US);

    private static String money(double amount) { return "$" + String.format(Locale.US, "%,.0f", amount); }

    /** a month of spending: everything but savings, investing and extra debt payments */
    static double spending(Map<String, Double> monthly) {
        return monthly.entrySet().stream().filter(e -> !BudgetFit.isSaving(e.getKey()))
                .mapToDouble(Map.Entry::getValue).sum();
    }

    /** `current`: the budget as it is now (a goal without a date keeps its line's amount) */
    @SuppressWarnings("unchecked")
    static List<Goal> goals(Map<String, Object> savings, Map<String, Double> current) {
        List<Goal> out = new ArrayList<>();
        if (!(savings.get("goals") instanceof List<?> list)) return out;
        for (Object o : list) {
            if (!(o instanceof Map<?, ?> m)) continue;
            Map<String, Object> g = (Map<String, Object>) m;
            String name = String.valueOf(g.getOrDefault("name", "")).strip();
            if (name.isEmpty()) continue;
            LocalDate date = BudgetQuizController.parseDay(g.get("targetDate"));
            double needed = QuizDetails.number(g.get("monthlyNeeded"));
            boolean kept = false;
            if (needed <= 0) {
                String line = BudgetLines.goal(name);
                double now = current.entrySet().stream().filter(e -> e.getKey().equalsIgnoreCase(line))
                        .mapToDouble(Map.Entry::getValue).findFirst().orElse(0);
                if (now > 0) { needed = now; kept = true; }
            }
            out.add(new Goal(name, QuizDetails.number(g.get("target")), QuizDetails.number(g.get("saved")), date, needed, kept));
        }
        return out;
    }

    /**
     * @param savings the quiz's {emergencySaved, emergencyMonths, goals} (empty: nothing is split)
     * @param locked  lines whose amounts are fixed (typed on the review screen)
     */
    static void apply(Map<String, Double> monthly, Map<String, String> why, Map<String, Object> savings, Set<String> locked) {
        apply(monthly, why, savings, locked, Map.of());
    }

    static void apply(Map<String, Double> monthly, Map<String, String> why, Map<String, Object> savings, Set<String> locked,
                      Map<String, Double> current) {
        if (savings == null || savings.isEmpty()) return;
        List<Goal> goals = goals(savings, current == null ? Map.of() : current);
        double emergencySaved = QuizDetails.number(savings.get("emergencySaved"));
        int months = Math.max(1, (int) QuizDetails.number(savings.getOrDefault("emergencyMonths", 3)));
        double spending = spending(monthly);
        double target = Math.round(spending * months);
        double gap = Math.max(0, target - emergencySaved);

        // everything set aside for these, as one amount (the AI keeps one Savings line)
        boolean fundLocked = locked.contains(BudgetLines.EMERGENCY_FUND);
        double pool = take(monthly, BudgetLines.SAVINGS, locked);
        if (!fundLocked) pool += take(monthly, BudgetLines.EMERGENCY_FUND, locked);
        for (Goal g : goals) pool += take(monthly, BudgetLines.goal(g.name()), locked);
        pool = Math.floor(pool);

        List<Goal> dated = goals.stream()
                .filter(g -> g.monthlyNeeded() > 0 && g.saved() < g.target() && !locked.contains(BudgetLines.goal(g.name())))
                .sorted(Comparator.comparing(Goal::date, Comparator.nullsLast(Comparator.naturalOrder())))
                .toList();
        Map<String, Double> given = new LinkedHashMap<>();
        double goalShare = gap > 0 && !fundLocked ? Math.floor(pool / 2) : pool;
        for (Goal g : dated) {
            double give = Math.min(Math.ceil(g.monthlyNeeded()), Math.min(goalShare, pool));
            if (give <= 0) continue;
            given.merge(g.name(), give, Double::sum);
            goalShare -= give;
            pool -= give;
        }
        double fund = 0;
        if (gap > 0 && !fundLocked) {
            fund = Math.min(pool, Math.ceil(gap));
            pool -= fund;
        }
        for (Goal g : dated) {
            double still = Math.ceil(g.monthlyNeeded()) - given.getOrDefault(g.name(), 0.0);
            double give = Math.min(still, pool);
            if (give <= 0) continue;
            given.merge(g.name(), give, Double::sum);
            pool -= give;
        }

        // the lines, with why
        boolean split = fund > 0 || !given.isEmpty();
        if (fund > 0) {
            monthly.put(BudgetLines.EMERGENCY_FUND, fund);
            long monthsToFull = (long) Math.ceil(gap / fund);
            why.put(BudgetLines.EMERGENCY_FUND, "Builds your emergency fund: " + money(emergencySaved) + " of " + money(target)
                    + " saved (" + months + " months of spending). At " + money(fund) + " a month it's full "
                    + (monthsToFull <= 1 ? "next month." : "in about " + monthsToFull + " months."));
        }
        for (Goal g : dated) {
            Double amount = given.get(g.name());
            if (amount == null) continue;
            String line = BudgetLines.goal(g.name());
            monthly.put(line, amount);
            String by = g.date() != null ? " by " + g.date().format(MONTH) : "";
            if (g.kept()) {
                why.put(line, amount >= Math.ceil(g.monthlyNeeded())
                        ? money(amount) + " a month, as you set it in your Plan."
                        : money(amount) + " of the " + money(Math.ceil(g.monthlyNeeded())) + " a month you set in your Plan; your emergency fund gets a share too.");
                continue;
            }
            why.put(line, amount >= Math.ceil(g.monthlyNeeded())
                    ? money(amount) + " a month reaches " + money(g.target()) + by + "."
                    : money(amount) + " of the " + money(Math.ceil(g.monthlyNeeded())) + " a month it needs to be ready" + by
                      + "; your emergency fund gets a share too.");
        }
        if (pool >= 1) {
            monthly.put(BudgetLines.SAVINGS, pool);
            if (split) why.put(BudgetLines.SAVINGS, "Left over after your emergency fund and goals: savings for anything else.");
        }
    }

    /** removes an unlocked line, returning its amount */
    private static double take(Map<String, Double> monthly, String line, Set<String> locked) {
        if (locked.contains(line)) return 0;
        Double amount = monthly.remove(line);
        return amount == null ? 0 : amount;
    }
}
