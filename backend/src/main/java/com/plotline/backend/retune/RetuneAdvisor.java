package com.plotline.backend.retune;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Compares the monthly budget with what was actually spent and suggests changes. It never just
 * raises a category to match spending: a raise has to be paid for, by a category that's spending
 * less than planned, by money the budget doesn't use yet, or (only if asked) by saving less.
 * When nothing can pay for it, the advice is to slow down. Every change waits for the person to
 * accept it.
 */
public final class RetuneAdvisor {

    private RetuneAdvisor() { }

    /** a suggested change; `changes` are the new monthly amounts (empty: advice only) */
    public record Suggestion(String id, String category, String kind, String title, String message,
                             Map<String, Double> changes, Alternative alternative) { }

    /** a second way to do it, e.g. "Take it from Savings instead" */
    public record Alternative(String label, String message, Map<String, Double> changes) { }

    public record Advice(List<String> warnings, List<Suggestion> suggestions) { }

    static final double MIN_GAP = 15;           // ignore differences smaller than this
    static final int MAX_SUGGESTIONS = 5;

    /** spending that comes in bursts (a $0 month says nothing): never lowered or used to pay for another */
    static final Set<String> BURSTY = Set.of("home", "travel", "trips", "gifts & donations", "gifts", "donations",
            "holidays & gifts", "car maintenance", "car registration", "clothing", "electronics", "medical",
            "pet care", "education", "insurance");

    static final Set<String> SAVING = Set.of("savings", "brokerage", "roth ira", "401k", "401k contribution",
            "401(k) contribution", "emergency fund", "investments", "investing");

    /** bills that don't shrink by trying harder: they can be raised (if affordable) but never give money away */
    static final Set<String> FIXED = Set.of("rent", "mortgage", "utilities", "internet", "phone", "renters insurance",
            "car insurance", "health insurance", "insurance", "childcare", "commute", "car payment", "tuition",
            "student loan", "subscriptions");

    static boolean isSaving(String category) {
        return SAVING.contains(key(category)) || com.plotline.backend.plan.BudgetLines.isPlanSaving(category);
    }

    static boolean isFixed(String category) {
        String k = key(category);
        return FIXED.contains(k) || k.startsWith("debt - ");
    }

    private static String key(String category) { return category.toLowerCase(Locale.ROOT).strip(); }

    /** rounded up to the next $5 */
    static double up5(double amount) { return Math.ceil(amount / 5.0) * 5.0; }

    private static String money(double amount) { return "$" + String.format(Locale.US, "%,.0f", amount); }

    /**
     * @param budget        monthly budget by category
     * @param actual        average monthly spending by category (from the months used)
     * @param takeHome      monthly take-home pay (0 if unknown)
     */
    public static Advice advise(Map<String, Double> budget, Map<String, Double> actual, double takeHome) {
        return advise(budget, List.of(actual), takeHome, Set.of());
    }

    /**
     * @param months    spending by category for each month compared (only months since the budget changed)
     * @param setAsides once-a-year costs set aside monthly (from the quiz): like bursty ones, never lowered
     */
    public static Advice advise(Map<String, Double> budget, List<Map<String, Double>> months, double takeHome, Set<String> setAsides) {
        // the average month, and each category's lowest and highest month (a change has to hold in all of them)
        Map<String, Double> actual = new LinkedHashMap<>(), lowest = new LinkedHashMap<>(), highest = new LinkedHashMap<>();
        java.util.Set<String> seen = new java.util.HashSet<>(budget.keySet());
        months.forEach(m -> seen.addAll(m.keySet()));
        for (String c : seen) {
            double sum = 0, lo = Double.MAX_VALUE, hi = 0;
            for (var m : months) {
                double v = m.getOrDefault(c, 0.0);
                sum += v;
                lo = Math.min(lo, v);
                hi = Math.max(hi, v);
            }
            if (sum > 0) actual.put(c, Math.round(sum / Math.max(1, months.size()) * 100) / 100.0);
            lowest.put(c, lo == Double.MAX_VALUE ? 0 : lo);
            highest.put(c, hi);
        }
        java.util.Set<String> bursty = new java.util.HashSet<>(BURSTY);
        setAsides.forEach(name -> bursty.add(key(name)));
        List<String> warnings = new ArrayList<>();
        List<Suggestion> suggestions = new ArrayList<>();

        double spentTotal = actual.entrySet().stream().filter(e -> !isSaving(e.getKey())).mapToDouble(Map.Entry::getValue).sum();
        if (takeHome > 0 && spentTotal > takeHome) {
            warnings.add("You're spending about " + money(spentTotal - takeHome) + " a month more than you bring home ("
                    + money(spentTotal) + " vs. " + money(takeHome) + "). Slowing down somewhere matters more than any budget change.");
        } else if (takeHome > 0 && spentTotal > takeHome * 0.95) {
            warnings.add("Your spending (" + money(spentTotal) + " a month) is close to your take-home (" + money(takeHome)
                    + "), which leaves little for saving.");
        }

        // money the budget doesn't hand out yet
        double budgetTotal = budget.values().stream().mapToDouble(Double::doubleValue).sum();
        double unassigned = takeHome > 0 ? Math.max(0, takeHome - budgetTotal) : 0;

        // categories spending less than planned can give the difference (never below what's spent)
        Map<String, Double> slack = new LinkedHashMap<>();
        // (not bursty ones; never below the busiest month, or half the budget; under in every month)
        for (var e : budget.entrySet()) {
            String c = e.getKey();
            if (isSaving(c) || isFixed(c) || bursty.contains(key(c))) continue;
            double room = e.getValue() - Math.max(up5(highest.getOrDefault(c, 0.0)), e.getValue() / 2);
            if (room >= MIN_GAP) slack.put(c, room);
        }

        // over budget, biggest gap first
        List<String> over = budget.keySet().stream()
                .filter(c -> !isSaving(c))
                .filter(c -> actual.getOrDefault(c, 0.0) > budget.get(c) * 1.10 && actual.getOrDefault(c, 0.0) - budget.get(c) >= MIN_GAP)
                .filter(c -> lowest.getOrDefault(c, 0.0) > budget.get(c))   // over in every month, not one big one
                .sorted(Comparator.comparingDouble((String c) -> actual.get(c) - budget.get(c)).reversed())
                .toList();

        Map<String, Double> savings = new LinkedHashMap<>();
        budget.forEach((c, v) -> { if (isSaving(c)) savings.put(c, v); });

        for (String category : over) {
            double planned = budget.get(category);
            double spent = actual.get(category);
            double target = up5(spent);
            double gap = target - planned;
            String opening = "You spend about " + money(spent) + " a month on " + category + ", more than the "
                    + money(planned) + " in your budget.";

            Map<String, Double> changes = new LinkedHashMap<>();
            List<String> donors = new ArrayList<>();
            double covered = 0;
            for (var donor : slack.entrySet().stream()
                    .sorted(Map.Entry.<String, Double>comparingByValue().reversed()).toList()) {
                if (covered >= gap) break;
                double take = Math.min(donor.getValue(), gap - covered);
                if (take < 5) continue;
                take = Math.floor(take / 5) * 5;
                if (take <= 0) continue;
                double newAmount = budget.get(donor.getKey()) - take;
                changes.put(donor.getKey(), newAmount);
                slack.put(donor.getKey(), donor.getValue() - take);
                covered += take;
                donors.add(donor.getKey() + " (" + money(actual.getOrDefault(donor.getKey(), 0.0)) + " of "
                        + money(budget.get(donor.getKey())) + ")");
            }
            slack.values().removeIf(v -> v < MIN_GAP);

            // whatever categories couldn't cover, money the budget doesn't use yet can
            double fromUnassigned = Math.min(unassigned, gap - covered);
            if (fromUnassigned >= 5) {
                fromUnassigned = Math.floor(fromUnassigned / 5) * 5;
                unassigned -= fromUnassigned;
                covered += fromUnassigned;
            } else {
                fromUnassigned = 0;
            }

            String id = "over:" + key(category);
            if (covered >= gap) {
                changes.put(category, target);
                StringBuilder message = new StringBuilder(opening);
                if (!donors.isEmpty()) message.append(" You spend less on ").append(String.join(" and ", donors))
                        .append(", so moving that money over covers it.");
                if (fromUnassigned > 0) message.append(" ").append(money(fromUnassigned))
                        .append(" comes from money your budget doesn't assign yet.");
                suggestions.add(new Suggestion(id, category, "rebalance", "Raise " + category + " to " + money(target),
                        message.toString(), changes, null));
            } else if (covered > 0) {
                double newAmount = planned + covered;
                changes.put(category, newAmount);
                double rest = gap - covered;
                suggestions.add(new Suggestion(id, category, "partial", "Raise " + category + " to " + money(newAmount) + " and slow down",
                        opening + " Other categories can cover " + money(covered) + " of the " + money(gap)
                                + ". Try to spend about " + money(rest) + " less a month on " + category
                                + " (" + money(rest * 12 / 52) + " a week).",
                        changes, savingsAlternative(category, planned, target, savings)));
            } else {
                String advice = isFixed(category)
                        ? " Nothing else in your budget has room for it, so this needs a bigger change: a cheaper plan, a roommate, or saving less for now."
                        : " Nothing else in your budget has room for it. Try to spend about " + money(gap) + " less a month on "
                          + category + " (" + money(gap * 12 / 52) + " a week).";
                suggestions.add(new Suggestion(id, category, "slowDown", "Slow down on " + category,
                        opening + advice, Map.of(), savingsAlternative(category, planned, target, savings)));
            }
        }

        // well under budget: lower it and save the difference
        // the emergency fund while it's being built (the quiz only gives it a line until it's full), then Savings
        String savingsCategory = savings.keySet().stream().filter(c -> key(c).equals("emergency fund")).findFirst()
                .or(() -> savings.keySet().stream().filter(c -> key(c).equals("savings")).findFirst())
                .orElse(savings.keySet().stream().findFirst().orElse(null));
        for (var e : slack.entrySet()) {
            String category = e.getKey();
            double planned = budget.get(category);
            double spent = actual.getOrDefault(category, 0.0);
            if (e.getValue() < 25 || spent > planned * 0.75) continue;
            double room = Math.floor(e.getValue() / 5) * 5;
            double newAmount = planned - room;
            Map<String, Double> changes = new LinkedHashMap<>();
            changes.put(category, newAmount);
            String where;
            if (savingsCategory != null) {
                changes.put(savingsCategory, budget.get(savingsCategory) + room);
                where = "add " + money(room) + " to " + savingsCategory;
            } else {
                where = "free up " + money(room);
            }
            suggestions.add(new Suggestion("under:" + key(category), category, "lower", "Lower " + category + " to " + money(newAmount),
                    "You spend about " + money(spent) + " a month on " + category + " but budget " + money(planned)
                            + ". Lower it to " + money(newAmount) + " and " + where + "?",
                    changes, null));
        }

        return new Advice(warnings, suggestions.subList(0, Math.min(MAX_SUGGESTIONS, suggestions.size())));
    }

    /** "Take it from Savings instead": offered only when savings can cover the whole raise */
    private static Alternative savingsAlternative(String category, double planned, double target, Map<String, Double> savings) {
        double gap = target - planned;
        for (var e : savings.entrySet()) {
            if (e.getValue() >= gap) {
                Map<String, Double> changes = new LinkedHashMap<>();
                changes.put(category, target);
                changes.put(e.getKey(), e.getValue() - gap);
                return new Alternative("Take " + money(gap) + " from " + e.getKey(),
                        "This raises " + category + " to " + money(target) + " by saving " + money(gap) + " less each month.",
                        changes);
            }
        }
        return null;
    }
}
