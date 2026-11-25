package com.plotline.backend.plan;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.plotline.backend.service.FixedCosts;

/**
 * Keeps the budget's Plan lines (see {@link BudgetLines}) in step when the plan is saved:
 *   - a debt's line is its minimum: added, renamed, changed or removed with the debt (a loan whose
 *     first payment is more than ~6 weeks away has no line yet, as in the quiz)
 *   - "Extra Debt Payment" is the payoff planner's extra
 *   - a renamed goal renames its line; a deleted goal's money goes back to Savings
 *   - a goal from "Can I afford it?" remembers the budget cuts that fund it ({line, amount}): once
 *     it's reached or deleted, those lines get their money back (any rest goes to Savings). A paused
 *     extra debt payment comes back through the plan's extraDebtPayment (see restoreExtraDebt).
 * Only what changed in the plan is touched, so other saves (adding money to a goal) leave the
 * budget alone. Monthly Costs' fixed lines follow the budget.
 */
@Component
public class PlanBudgetSync {
    private static final Logger log = LoggerFactory.getLogger(PlanBudgetSync.class);

    /** like the quiz: a loan that starts this much later isn't budgeted yet */
    static final int STARTS_LATER_DAYS = 45;

    private final BudgetFiles files;
    private final FixedCosts fixedCosts;

    public PlanBudgetSync(BudgetFiles files, FixedCosts fixedCosts) {
        this.files = files;
        this.fixedCosts = fixedCosts;
    }

    /** @return whether the budget changed */
    public boolean apply(String user, JsonNode before, JsonNode after) {
        Map<String, Double> budget = new LinkedHashMap<>(files.monthly(user));
        if (budget.isEmpty()) return false; // no budget yet: the quiz builds the lines
        boolean changed = applyTo(budget, before, after, LocalDate.now());
        if (!changed) return false;
        try {
            files.save(user, budget);
            fixedCosts.applyQuizBudget(user, budget);
        } catch (Exception e) {
            log.warn("Updating the budget from the plan failed for {}: {}", user, e.getMessage());
            return false;
        }
        return true;
    }

    /** the changes, on `budget` (whole dollars) */
    static boolean applyTo(Map<String, Double> budget, JsonNode before, JsonNode after, LocalDate today) {
        boolean changed = false;

        Map<String, JsonNode> oldDebts = byId(before, "debts"), newDebts = byId(after, "debts");
        for (var old : oldDebts.entrySet()) {
            if (!newDebts.containsKey(old.getKey())) changed |= remove(budget, BudgetLines.debt(name(old.getValue()))) != null;
        }
        for (var entry : newDebts.entrySet()) {
            JsonNode debt = entry.getValue(), old = oldDebts.get(entry.getKey());
            if (name(debt).isEmpty()) continue;
            if (old != null && name(old).equals(name(debt)) && number(old, "minPayment") == number(debt, "minPayment")
                    && Objects.equals(text(old, "dueDate"), text(debt, "dueDate"))) continue;
            String line = BudgetLines.debt(name(debt));
            if (old != null && !name(old).equals(name(debt))) changed |= rename(budget, BudgetLines.debt(name(old)), line);
            double minimum = Math.round(number(debt, "minPayment"));
            if (minimum > 0 && !startsLater(text(debt, "dueDate"), today)) {
                changed |= set(budget, line, minimum);
            } else {
                changed |= remove(budget, line) != null;
            }
        }

        double oldExtra = Math.round(number(before, "extraDebtPayment")), newExtra = Math.round(number(after, "extraDebtPayment"));
        if (oldExtra != newExtra) {
            if (newExtra > 0) changed |= set(budget, BudgetLines.EXTRA_DEBT, newExtra);
            else changed |= remove(budget, BudgetLines.EXTRA_DEBT) != null;
        }

        Map<String, JsonNode> oldGoals = byId(before, "savingsGoals"), newGoals = byId(after, "savingsGoals");
        for (var old : oldGoals.entrySet()) {
            JsonNode now = newGoals.get(old.getKey());
            String oldLine = BudgetLines.goal(name(old.getValue()));
            if (now == null) {
                Double freed = remove(budget, oldLine);
                if (freed != null) {
                    changed = true;
                    giveBack(budget, freed, old.getValue().path("cuts"));
                }
            } else if (reached(old.getValue(), now) && now.path("cuts").isArray() && now.get("cuts").size() > 0
                    && find(budget, BudgetLines.goal(name(now))) != null) {
                // reached: the cuts that paid for it end
                double freed = remove(budget, BudgetLines.goal(name(now)));
                giveBack(budget, freed, now.path("cuts"));
                changed = true;
            } else if (!name(now).isEmpty() && !name(now).equals(name(old.getValue()))) {
                changed |= rename(budget, oldLine, BudgetLines.goal(name(now)));
            }
        }
        return changed;
    }

    /**
     * Before an ending goal (reached or deleted) is synced: an extra debt payment its cuts paused goes
     * back into the debt planner (the plan's extraDebtPayment), so the planner and the budget agree.
     * The budget line follows from that change; giveBack doesn't add it again.
     * @return whether the plan changed
     */
    public static boolean restoreExtraDebt(JsonNode before, ObjectNode after) {
        double add = 0;
        Map<String, JsonNode> oldGoals = byId(before, "savingsGoals"), newGoals = byId(after, "savingsGoals");
        for (String id : endedGoals(before, after)) {
            JsonNode now = newGoals.get(id);
            JsonNode cuts = (now != null ? now : oldGoals.get(id)).path("cuts");
            for (JsonNode cut : cuts) {
                if (BudgetLines.isExtraDebt(cut.path("line").asText(""))) add += cut.path("amount").asDouble();
            }
        }
        if (add <= 0) return false;
        after.put("extraDebtPayment", Math.round(number(after, "extraDebtPayment") + add));
        return true;
    }

    /** goals that ended in this save: deleted, or just reached */
    public static java.util.Set<String> endedGoals(JsonNode before, JsonNode after) {
        java.util.Set<String> out = new java.util.LinkedHashSet<>();
        Map<String, JsonNode> newGoals = byId(after, "savingsGoals");
        for (var old : byId(before, "savingsGoals").entrySet()) {
            JsonNode now = newGoals.get(old.getKey());
            if (now == null || reached(old.getValue(), now)) out.add(old.getKey());
        }
        return out;
    }

    private static boolean reached(JsonNode before, JsonNode after) {
        double target = number(after, "target");
        return target > 0 && number(before, "saved") < target && number(after, "saved") >= target;
    }

    /** a goal's money back to the lines its cuts came from (in order), the rest to Savings */
    private static void giveBack(Map<String, Double> budget, double freed, JsonNode cuts) {
        double left = freed;
        if (cuts != null && cuts.isArray()) {
            for (JsonNode cut : cuts) {
                String line = cut.path("line").asText("").strip();
                double amount = Math.min(left, cut.path("amount").asDouble());
                if (line.isEmpty() || amount <= 0) continue;
                if (BudgetLines.isExtraDebt(line)) {
                    left -= amount;   // back through the plan's extraDebtPayment (restoreExtraDebt)
                    continue;
                }
                String key = find(budget, line);
                budget.merge(key != null ? key : line, amount, Double::sum);
                left -= amount;
            }
        }
        if (left > 0) budget.merge(BudgetLines.SAVINGS, left, Double::sum);
    }

    static boolean startsLater(String dueDate, LocalDate today) {
        if (dueDate == null || dueDate.isBlank()) return false;
        try {
            return LocalDate.parse(dueDate.length() >= 10 ? dueDate.substring(0, 10) : dueDate).isAfter(today.plusDays(STARTS_LATER_DAYS));
        } catch (Exception e) {
            return false;
        }
    }

    // ── budget lines (matched ignoring case, like the rest of the app) ─────

    private static String find(Map<String, Double> budget, String line) {
        return budget.keySet().stream().filter(k -> k.equalsIgnoreCase(line)).findFirst().orElse(null);
    }

    private static boolean set(Map<String, Double> budget, String line, double amount) {
        String key = find(budget, line);
        if (key != null && budget.get(key) == amount) return false;
        budget.put(key != null ? key : line, amount);
        return true;
    }

    /** the line's amount, or null if it wasn't there */
    private static Double remove(Map<String, Double> budget, String line) {
        String key = find(budget, line);
        return key == null ? null : budget.remove(key);
    }

    /** keeps the line where it was in the budget; adds to a line already called that */
    private static boolean rename(Map<String, Double> budget, String from, String to) {
        String key = find(budget, from);
        if (key == null || key.equals(to)) return false;
        double amount = budget.get(key);
        String existing = find(budget, to);
        Map<String, Double> copy = new LinkedHashMap<>(budget);
        budget.clear();
        copy.forEach((k, v) -> {
            if (k.equals(key)) {
                if (existing == null) budget.put(to, amount);
            } else {
                budget.put(k, k.equals(existing) ? v + amount : v);
            }
        });
        return true;
    }

    // ── the plan's JSON ────────────────────────────────────────────────────

    private static Map<String, JsonNode> byId(JsonNode plan, String field) {
        Map<String, JsonNode> out = new LinkedHashMap<>();
        if (plan == null || !plan.path(field).isArray()) return out;
        for (JsonNode item : plan.get(field)) {
            String id = item.path("id").asText("");
            if (!id.isEmpty()) out.put(id, item);
        }
        return out;
    }

    private static String name(JsonNode item) { return item.path("name").asText("").strip(); }

    private static double number(JsonNode node, String field) {
        return node != null && node.path(field).isNumber() ? node.get(field).asDouble() : 0;
    }

    private static String text(JsonNode node, String field) {
        return node != null && node.path(field).isTextual() ? node.get(field).asText() : null;
    }
}
