package com.plotline.backend.service;

import java.io.ByteArrayInputStream;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.stereotype.Component;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Fixed monthly costs (users/<u>/fixed_costs.json: [{id, category, amount, source?}]): counted in every
 * month without being entered. The budget quiz adds its fixed lines (savings and investing, bills,
 * subscriptions, debt minimums, source "quiz"); one removed on Monthly Costs isn't added again
 * (users/<u>/fixed-costs-removed.json).
 *
 * Never counted twice: bank sync skips transactions in a fixed category, and a month's total for a
 * fixed category is the fixed amount or what was recorded there (older syncs, receipts), whichever
 * is larger — never both.
 */
@Component
public class FixedCosts {

    /** quiz lines that are the same every month */
    static final Set<String> FROM_QUIZ = Set.of(
            // saving and investing
            "savings", "emergency fund", "roth ira", "brokerage", "investments", "investing", "hsa",
            // bills that are the same each month (not utilities: they change with use, so they're tracked
            // from the bank or entered on the day the bill is paid)
            "rent", "mortgage", "internet", "phone", "car payment", "car insurance", "insurance",
            "renters insurance", "health insurance",
            "subscriptions");

    private final S3Service s3;
    private final ObjectMapper json = new ObjectMapper();

    public FixedCosts(S3Service s3) {
        this.s3 = s3;
    }

    public static boolean fromQuiz(String category) {
        String c = category == null ? "" : category.strip().toLowerCase(Locale.ROOT);
        return FROM_QUIZ.contains(c) || c.startsWith("debt - ") || com.plotline.backend.plan.BudgetLines.isPlanSaving(c);
    }

    public List<Map<String, Object>> load(String username) {
        try {
            byte[] data = s3.downloadFile("users/" + username + "/fixed_costs.json");
            if (data == null || data.length == 0) return new ArrayList<>();
            return json.readValue(data, new TypeReference<List<Map<String, Object>>>() {});
        } catch (Exception e) {
            return new ArrayList<>();
        }
    }

    public void save(String username, List<Map<String, Object>> fixed) throws Exception {
        write("users/" + username + "/fixed_costs.json", json.writeValueAsBytes(fixed));
    }

    /** the fixed categories, lower-cased (bank sync skips them) */
    public Set<String> categories(String username) {
        return load(username).stream().map(fc -> String.valueOf(fc.get("category")).toLowerCase(Locale.ROOT))
                .collect(Collectors.toSet());
    }

    static double amount(Map<String, Object> fc) {
        return fc.get("amount") instanceof Number n ? n.doubleValue() : 0.0;
    }

    /** a month's totals with the fixed costs counted once: the fixed amount or what was recorded, whichever is larger */
    public static void countOnce(Map<String, Double> totals, List<Map<String, Object>> fixed) {
        for (var fc : fixed) {
            double amount = amount(fc);
            if (amount <= 0) continue;
            String category = String.valueOf(fc.get("category"));
            String key = totals.keySet().stream().filter(k -> k.equalsIgnoreCase(category)).findFirst().orElse(category);
            totals.put(key, Math.round(Math.max(totals.getOrDefault(key, 0.0), amount) * 100) / 100.0);
        }
    }

    /** the same for a map of numbers stored as objects (the monthly period JSON) */
    public static void countOnceInObjects(Map<String, Object> totals, List<Map<String, Object>> fixed) {
        Map<String, Double> numbers = new LinkedHashMap<>();
        totals.forEach((k, v) -> numbers.put(k, v instanceof Number n ? n.doubleValue() : 0.0));
        countOnce(numbers, fixed);
        totals.putAll(numbers);
    }

    // ── from the budget quiz ───────────────────────────────────────────────

    private Set<String> removed(String username) {
        try {
            byte[] data = s3.downloadFile("users/" + username + "/fixed-costs-removed.json");
            if (data == null || data.length == 0) return new LinkedHashSet<>();
            return new LinkedHashSet<>(json.readValue(data, new TypeReference<List<String>>() {}));
        } catch (Exception e) {
            return new LinkedHashSet<>();
        }
    }

    /** a quiz line removed on Monthly Costs: the quiz doesn't add it again */
    public void rememberRemoved(String username, String category) throws Exception {
        Set<String> removed = removed(username);
        removed.add(category.toLowerCase(Locale.ROOT));
        write("users/" + username + "/fixed-costs-removed.json", json.writeValueAsBytes(new ArrayList<>(removed)));
    }

    /**
     * After the quiz is saved: its fixed lines at the budget's amounts. A quiz line no longer in the
     * budget is dropped; fixed costs they added themselves are left alone (even with the same name).
     */
    public List<Map<String, Object>> applyQuizBudget(String username, Map<String, Double> monthly) throws Exception {
        Set<String> removed = removed(username);
        List<Map<String, Object>> fixed = load(username);
        Map<String, Double> wanted = new LinkedHashMap<>();
        monthly.forEach((category, amount) -> {
            if (fromQuiz(category) && amount != null && amount > 0 && !removed.contains(category.toLowerCase(Locale.ROOT)))
                wanted.put(category, Math.round(amount * 100) / 100.0);
        });
        fixed.removeIf(fc -> "quiz".equals(fc.get("source"))
                && wanted.keySet().stream().noneMatch(c -> c.equalsIgnoreCase(String.valueOf(fc.get("category")))));
        wanted.forEach((category, amount) -> {
            Map<String, Object> existing = fixed.stream()
                    .filter(fc -> category.equalsIgnoreCase(String.valueOf(fc.get("category")))).findFirst().orElse(null);
            if (existing == null) {
                Map<String, Object> entry = new LinkedHashMap<>();
                entry.put("id", UUID.randomUUID().toString());
                entry.put("category", category);
                entry.put("amount", amount);
                entry.put("source", "quiz");
                fixed.add(entry);
            } else if ("quiz".equals(existing.get("source"))) {
                existing.put("amount", amount);
            }
        });
        save(username, fixed);
        return fixed;
    }

    private void write(String key, byte[] bytes) throws Exception {
        try (var in = new ByteArrayInputStream(bytes)) {
            s3.uploadFile(key, in, bytes.length);
        }
    }
}
