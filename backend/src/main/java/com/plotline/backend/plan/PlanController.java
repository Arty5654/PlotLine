package com.plotline.backend.plan;

import static com.plotline.backend.util.UsernameUtils.normalize;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.service.FixedCosts;
import com.plotline.backend.service.S3Service;

/**
 * Budget → Plan: savings goals, the emergency fund and debts for the payoff planner.
 * One document per person (users/<name>/plan.json); the app does the math. Saving it keeps the
 * budget's debt and goal lines in step (PlanBudgetSync), and POST budget-line sets how much the
 * budget puts toward the emergency fund or a goal.
 */
@RestController
@RequestMapping("/api/plan")
public class PlanController {

    static final int MAX_BYTES = 200_000;

    private final S3Service s3;
    private final PlanBudgetSync sync;
    private final BudgetFiles budgets;
    private final FixedCosts fixedCosts;
    private final com.plotline.backend.afford.SubscriptionPauses pauses;
    private final ObjectMapper json = new ObjectMapper();

    public PlanController(S3Service s3, PlanBudgetSync sync, BudgetFiles budgets, FixedCosts fixedCosts,
                          com.plotline.backend.afford.SubscriptionPauses pauses) {
        this.s3 = s3;
        this.sync = sync;
        this.budgets = budgets;
        this.fixedCosts = fixedCosts;
        this.pauses = pauses;
    }

    private JsonNode saved(String username) {
        try {
            return json.readTree(s3.downloadFile(key(username)));
        } catch (Exception e) {
            return json.createObjectNode();
        }
    }

    /** users/{u}/plan.json */
    public static String planKey(String username) { return key(username); }

    private static String key(String username) {
        return "users/" + normalize(username) + "/plan.json";
    }

    @GetMapping("/{username}")
    public ResponseEntity<JsonNode> get(@PathVariable String username) {
        return ResponseEntity.ok(saved(username)); // empty: nothing planned yet
    }

    @PutMapping("/{username}")
    public ResponseEntity<?> put(@PathVariable String username, @RequestBody JsonNode plan) throws Exception {
        if (plan == null || !plan.isObject()) return ResponseEntity.badRequest().body("Expected an object");
        JsonNode before = saved(username);
        // a "Can I afford it?" goal that ends gives a paused extra debt payment back to the planner
        PlanBudgetSync.restoreExtraDebt(before, (com.fasterxml.jackson.databind.node.ObjectNode) plan);
        java.util.Set<String> ended = PlanBudgetSync.endedGoals(before, plan);
        byte[] bytes = json.writeValueAsBytes(plan);
        if (bytes.length > MAX_BYTES) return ResponseEntity.badRequest().body("That plan is too large");
        try (var in = new ByteArrayInputStream(bytes)) {
            s3.uploadFile(key(username), in, bytes.length);
        }
        sync.apply(normalize(username), before, plan);
        pauses.resume(normalize(username), ended);   // subscriptions paused for an ended goal
        return ResponseEntity.ok(plan);
    }

    /**
     * {line: "Emergency Fund" | "Savings - <goal>", amount, from?: "Savings" | "unassigned" | another
     * Plan line}: sets what the budget puts toward it each month. More comes from `from` (default:
     * Savings, then money the budget doesn't assign yet); less goes back to Savings. 409 with
     * {available} when there isn't enough; nothing changes then.
     */
    @PostMapping("/{username}/budget-line")
    public ResponseEntity<?> budgetLine(@PathVariable String username, @RequestBody Map<String, Object> body) throws Exception {
        String user = normalize(username);
        String line = String.valueOf(body.getOrDefault("line", "")).strip();
        double amount = body.get("amount") instanceof Number n ? Math.round(n.doubleValue()) : -1;
        String from = body.get("from") == null ? null : String.valueOf(body.get("from")).strip();
        if (amount < 0 || amount > 1_000_000 || !isPlanLine(user, line) || (from != null && !from.equals("unassigned")
                && !from.equalsIgnoreCase(BudgetLines.SAVINGS) && !isPlanLine(user, from))) {
            return ResponseEntity.badRequest().body(Map.of("error", "That isn't a savings line in your plan."));
        }
        Map<String, Double> budget = new LinkedHashMap<>(budgets.monthly(user));
        if (budget.isEmpty()) return ResponseEntity.badRequest().body(Map.of("error", "Take the budget quiz first."));
        String key = budget.keySet().stream().filter(k -> k.equalsIgnoreCase(line)).findFirst().orElse(line);
        double delta = amount - budget.getOrDefault(key, 0.0);

        if (delta > 0) {
            List<String> sources = from != null ? List.of(from) : List.of(BudgetLines.SAVINGS, "unassigned");
            double total = budget.values().stream().mapToDouble(Double::doubleValue).sum();
            double unassigned = Math.max(0, Math.floor(budgets.takeHome(user) - total));
            Map<String, Double> take = new LinkedHashMap<>();
            double left = delta;
            for (String source : sources) {
                if (left <= 0) break;
                if (source.equals("unassigned")) {
                    double t = Math.min(left, unassigned);
                    if (t > 0) take.put(source, t);
                    left -= t;
                } else {
                    String sourceKey = budget.keySet().stream().filter(k -> k.equalsIgnoreCase(source)).findFirst().orElse(null);
                    if (sourceKey == null || sourceKey.equals(key)) continue;
                    double t = Math.min(left, budget.get(sourceKey));
                    if (t > 0) take.put(sourceKey, t);
                    left -= t;
                }
            }
            if (left > 0) return ResponseEntity.status(409).body(Map.of("available", delta - left + budget.getOrDefault(key, 0.0)));
            take.forEach((source, t) -> {
                if (source.equals("unassigned")) return;
                double rest = budget.get(source) - t;
                if (rest > 0) budget.put(source, rest); else budget.remove(source);
            });
        } else if (delta < 0) {
            budget.merge(BudgetLines.SAVINGS, -delta, Double::sum);
        }
        if (amount > 0) budget.put(key, amount); else budget.remove(key);
        budgets.save(user, budget);
        fixedCosts.applyQuizBudget(user, budget);
        return ResponseEntity.ok(Map.of("budget", budget));
    }

    /** the emergency fund, or one of the plan's savings goals */
    private boolean isPlanLine(String user, String line) {
        if (line.equalsIgnoreCase(BudgetLines.EMERGENCY_FUND)) return true;
        if (!BudgetLines.isGoal(line)) return false;
        for (JsonNode goal : saved(user).path("savingsGoals")) {
            if (BudgetLines.goal(goal.path("name").asText("")).equalsIgnoreCase(line)) return true;
        }
        return false;
    }

    static String text(byte[] bytes) {
        return new String(bytes, StandardCharsets.UTF_8);
    }
}
