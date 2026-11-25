package com.plotline.backend.plan;

import java.io.ByteArrayInputStream;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.plotline.backend.service.FixedCosts;
import com.plotline.backend.service.S3Service;

/**
 * What every change to the monthly budget made outside the Plan tab does next (the Monthly Budget
 * editor, retune suggestions, Track Subscriptions, Revert):
 *   - Monthly Costs' fixed lines follow the budget (FixedCosts.applyQuizBudget)
 *   - the debt planner follows a debt's line (its minimum) and "Extra Debt Payment" (the extra)
 * Goal lines need nothing: the Plan tab reads them from the budget.
 */
@Component
public class BudgetSaves {
    private static final Logger log = LoggerFactory.getLogger(BudgetSaves.class);

    private final S3Service s3;
    private final FixedCosts fixedCosts;
    private final ObjectMapper json = new ObjectMapper();

    public BudgetSaves(S3Service s3, FixedCosts fixedCosts) {
        this.s3 = s3;
        this.fixedCosts = fixedCosts;
    }

    /** after the monthly budget changed from `before` to `after` (both saved already) */
    public void changed(String user, Map<String, Double> before, Map<String, Double> after) {
        try {
            fixedCosts.applyQuizBudget(user, after);
        } catch (Exception e) {
            log.warn("Couldn't update fixed costs for {}: {}", user, e.getMessage());
        }
        planFollows(user, before, after);
    }

    /** the debt planner's minimums and extra payment, from the lines that changed */
    void planFollows(String user, Map<String, Double> before, Map<String, Double> after) {
        JsonNode node = readPlan(user);
        if (!(node instanceof ObjectNode plan)) return;
        boolean changed = applyTo(plan, before, after);
        if (!changed) return;
        try {
            byte[] bytes = json.writeValueAsBytes(plan);
            s3.uploadFile(PlanController.planKey(user), new ByteArrayInputStream(bytes), bytes.length);
        } catch (Exception e) {
            log.warn("Couldn't update the plan for {}: {}", user, e.getMessage());
        }
    }

    /** on `plan`: changed debt lines set that debt's minimum, a changed extra line the extra */
    static boolean applyTo(ObjectNode plan, Map<String, Double> before, Map<String, Double> after) {
        boolean changed = false;
        Double oldExtra = find(before, BudgetLines.EXTRA_DEBT), newExtra = find(after, BudgetLines.EXTRA_DEBT);
        if (!Objects.equals(round(oldExtra), round(newExtra)) && plan.path("debts").size() > 0) {
            plan.put("extraDebtPayment", newExtra == null ? 0 : Math.round(newExtra));
            changed = true;
        }
        for (JsonNode d : plan.path("debts")) {
            if (!(d instanceof ObjectNode debt)) continue;
            String line = BudgetLines.debt(debt.path("name").asText(""));
            Double was = find(before, line), now = find(after, line);
            // a line removed in the editor leaves the debt alone (it may start later, or be paid off)
            if (now == null || Objects.equals(round(was), round(now))) continue;
            debt.put("minPayment", round(now));
            changed = true;
        }
        return changed;
    }

    private static Double find(Map<String, Double> budget, String line) {
        if (budget == null) return null;
        String k = line.strip().toLowerCase(Locale.ROOT);
        return budget.entrySet().stream().filter(e -> e.getKey().strip().toLowerCase(Locale.ROOT).equals(k))
                .map(Map.Entry::getValue).findFirst().orElse(null);
    }

    private static Double round(Double v) { return v == null ? null : Math.round(v * 100) / 100.0; }

    private JsonNode readPlan(String user) {
        try {
            byte[] data = s3.downloadFile(PlanController.planKey(user));
            return data == null || data.length == 0 ? null : json.readTree(data);
        } catch (Exception e) {
            return null;
        }
    }

    /** lines the Plan tab manages: they keep their current amounts when the budget is reverted */
    static boolean planManaged(String line) {
        String k = line == null ? "" : line.strip().toLowerCase(Locale.ROOT);
        return BudgetLines.isGoal(line) || BudgetLines.isDebt(line) || BudgetLines.isExtraDebt(line)
                || k.equals(BudgetLines.EMERGENCY_FUND.toLowerCase(Locale.ROOT)) || k.equals(BudgetLines.SAVINGS.toLowerCase(Locale.ROOT));
    }

    /**
     * "Revert to LLM Budget": the quiz's budget for everything they edited by hand, with what the
     * Plan manages kept as it is now (goal and debt lines, the extra payment, the emergency fund,
     * Savings) and the cuts of goals still being saved for ("Can I afford it?") still made.
     */
    public static Map<String, Double> reverted(Map<String, Double> original, Map<String, Double> current, JsonNode plan) {
        Map<String, Double> out = new LinkedHashMap<>();
        original.forEach((line, amount) -> { if (!planManaged(line)) out.put(line, amount); });
        current.forEach((line, amount) -> { if (planManaged(line)) out.put(line, amount); });
        for (JsonNode goal : plan == null ? com.fasterxml.jackson.databind.node.MissingNode.getInstance() : plan.path("savingsGoals")) {
            for (JsonNode cut : goal.path("cuts")) {
                String line = cut.path("line").asText("");
                if (line.isBlank() || planManaged(line)) continue;
                String key = out.keySet().stream().filter(k -> k.equalsIgnoreCase(line.strip())).findFirst().orElse(null);
                if (key == null) continue;
                double rest = out.get(key) - cut.path("amount").asDouble();
                if (rest >= 1) out.put(key, Math.round(rest * 100) / 100.0); else out.remove(key);
            }
        }
        return out;
    }

    /** reverts the budget (see {@link #reverted}); false when there's no quiz budget to go back to */
    public boolean revert(String user, BudgetFiles files) throws Exception {
        Map<String, Double> original = files.original(user);
        if (original.isEmpty()) return false;
        Map<String, Double> current = copy(files.monthly(user));
        Map<String, Double> result = reverted(original, current, readPlan(user));
        files.save(user, result);   // the monthly budget and its weekly copy
        changed(user, current, result);
        return true;
    }

    /** a copy (callers keep `before` while they change the budget) */
    public static Map<String, Double> copy(Map<String, Double> budget) {
        return budget == null ? new LinkedHashMap<>() : new LinkedHashMap<>(budget);
    }
}
