package com.plotline.backend.retune;

import static com.plotline.backend.util.UsernameUtils.normalize;

import java.io.ByteArrayInputStream;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.BudgetRequest;
import com.plotline.backend.plaid.TokenStore;
import com.plotline.backend.service.S3Service;

/**
 * Budgeting → "Tune your budget": the budget is compared with what was really spent and changes are
 * suggested. Only whole months that started after the budget last changed count (up to the last 3),
 * so the first suggestions come after a full month with the budget, then again as each month ends
 * (it used to judge a brand-new budget by months from before it). Nothing changes until applied.
 */
@RestController
@RequestMapping("/api/budget/{username}/retune")
public class RetuneController {

    static final int MONTHS = 3;

    private final S3Service s3;
    private final TokenStore tokens;
    private final ObjectMapper json = new ObjectMapper();

    private final com.plotline.backend.service.BudgetChanges budgetChanges;

    public RetuneController(S3Service s3, TokenStore tokens, com.plotline.backend.service.BudgetChanges budgetChanges) {
        this.s3 = s3;
        this.tokens = tokens;
        this.budgetChanges = budgetChanges;
    }

    @GetMapping
    public Map<String, Object> suggestions(@PathVariable String username) {
        String user = normalize(username);
        Map<String, Object> out = new LinkedHashMap<>();
        boolean bankLinked = !tokens.listAccessTokens(user).isEmpty() || !tokens.listAccessTokens(username).isEmpty();
        Map<String, Double> budget = loadBudget(user);
        out.put("bankLinked", bankLinked);
        if (!bankLinked || budget.isEmpty()) {
            out.put("ready", false);
            return out;
        }

        // the last complete months that have spending in them, all since the budget last changed
        LocalDate changed = budgetChanges.lastChange(user);
        List<String> used = new ArrayList<>();
        List<Map<String, Double>> months = new ArrayList<>();
        Map<String, Double> totals = new LinkedHashMap<>();
        YearMonth month = YearMonth.from(LocalDate.now()).minusMonths(1);
        for (int i = 0; i < MONTHS; i++, month = month.minusMonths(1)) {
            if (changed != null && month.atDay(1).isBefore(changed)) break; // before this budget
            Map<String, Double> spent = numbers(read("users/%s/costs/monthly/%s.json".formatted(user, month)).get("totals"));
            if (spent.values().stream().mapToDouble(Double::doubleValue).sum() <= 0) continue;
            used.add(month.toString());
            months.add(spent);
            spent.forEach((c, v) -> totals.merge(c, v, Double::sum));
        }
        out.put("monthsUsed", used);
        if (used.isEmpty()) {
            // not a full month with this budget yet: the first check is after the first whole month ends
            out.put("ready", false);
            if (changed != null) {
                YearMonth first = changed.getDayOfMonth() == 1 ? YearMonth.from(changed) : YearMonth.from(changed).plusMonths(1);
                out.put("firstCheck", first.plusMonths(1).atDay(1).toString());
            }
            return out;
        }
        Map<String, Double> average = new LinkedHashMap<>();
        totals.forEach((c, v) -> average.put(c, Math.round(v / used.size() * 100) / 100.0));

        double takeHome = 0;
        Object net = read("users/%s/last_budget_quiz.json".formatted(user)).get("monthlyNet");
        if (net instanceof Number n) takeHome = n.doubleValue();

        // once-a-year set-asides from the quiz: like other bursty spending, never lowered
        java.util.Set<String> setAsides = new java.util.HashSet<>();
        if (read("users/%s/last_budget_quiz.json".formatted(user)).get("otherCosts") instanceof Map<?, ?> other
                && other.get("yearly") instanceof List<?> yearly) {
            for (Object item : yearly) if (item instanceof Map<?, ?> m && m.get("name") != null) setAsides.add(String.valueOf(m.get("name")));
        }
        RetuneAdvisor.Advice advice = RetuneAdvisor.advise(budget, months, takeHome, setAsides);
        out.put("ready", true);
        out.put("averageSpending", average);
        out.put("warnings", advice.warnings());
        out.put("suggestions", advice.suggestions());
        return out;
    }

    /** {changes: {"Groceries": 340, "Eating Out": 120}} → the monthly (and weekly) budget, updated */
    @PostMapping("/apply")
    public ResponseEntity<?> apply(@PathVariable String username, @RequestBody Map<String, Object> body) throws Exception {
        String user = normalize(username);
        Map<String, Double> changes = numbers(body.get("changes"));
        if (changes.isEmpty() || changes.values().stream().anyMatch(v -> v < 0 || v > 1_000_000)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Nothing to change."));
        }
        Map<String, Double> monthly = new LinkedHashMap<>(loadBudget(user));
        if (monthly.isEmpty()) return ResponseEntity.badRequest().body(Map.of("error", "Take the budget quiz first."));
        monthly.putAll(changes);
        Map<String, Double> weekly = new LinkedHashMap<>();
        monthly.forEach((c, v) -> weekly.put(c, v / 4.0)); // the same weekly split as saving the budget elsewhere
        save(user, "monthly", monthly);
        save(user, "weekly", weekly);
        budgetChanges.record(user); // the next suggestions wait for a full month with this budget
        return ResponseEntity.ok(monthly);
    }

    /** the edited monthly budget, or the quiz's original */
    Map<String, Double> loadBudget(String user) {
        Map<String, Object> edited = read("users/%s/monthly-budget-edited.json".formatted(user));
        if (edited.get("budget") instanceof Map<?, ?>) return numbers(edited.get("budget"));
        return numbers(read("users/%s/monthly-budget.json".formatted(user)));
    }

    private void save(String user, String type, Map<String, Double> budget) throws Exception {
        byte[] bytes = json.writeValueAsBytes(new BudgetRequest(user, type, budget));
        s3.uploadFile("users/%s/%s-budget-edited.json".formatted(user, type), new ByteArrayInputStream(bytes), bytes.length);
    }

    private Map<String, Object> read(String key) {
        try {
            return json.readValue(s3.downloadFile(key), new TypeReference<Map<String, Object>>() {});
        } catch (Exception e) {
            return Map.of();
        }
    }

    private static Map<String, Double> numbers(Object value) {
        Map<String, Double> out = new LinkedHashMap<>();
        if (value instanceof Map<?, ?> m) {
            m.forEach((k, v) -> { if (v instanceof Number n) out.put(String.valueOf(k), n.doubleValue()); });
        }
        return out;
    }
}
