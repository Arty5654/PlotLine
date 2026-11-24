package com.plotline.backend.plan;

import java.io.ByteArrayInputStream;
import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.stereotype.Component;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.BudgetRequest;
import com.plotline.backend.service.S3Service;

/**
 * The current monthly budget (the "-edited" copy everything reads, else the quiz's original) and
 * take-home from the last quiz, for changes Plan makes to the budget's lines.
 */
@Component
public class BudgetFiles {

    private final S3Service s3;
    private final ObjectMapper json = new ObjectMapper();

    public BudgetFiles(S3Service s3) {
        this.s3 = s3;
    }

    /** category → monthly amount (empty before the budget quiz) */
    public Map<String, Double> monthly(String user) {
        Map<String, Object> edited = read("users/%s/monthly-budget-edited.json".formatted(user));
        if (edited.get("budget") instanceof Map<?, ?> m) return numbers(m);
        return numbers(read("users/%s/monthly-budget.json".formatted(user)));
    }

    /** the monthly budget and its weekly copy, in the format POST /api/budget saves */
    public void save(String user, Map<String, Double> monthly) throws Exception {
        Map<String, Double> weekly = new LinkedHashMap<>();
        monthly.forEach((c, v) -> weekly.put(c, v / 4.0));
        for (var copy : Map.of("monthly", monthly, "weekly", weekly).entrySet()) {
            byte[] bytes = json.writeValueAsBytes(new BudgetRequest(user, copy.getKey(), copy.getValue()));
            s3.uploadFile("users/%s/%s-budget-edited.json".formatted(user, copy.getKey()), new ByteArrayInputStream(bytes), bytes.length);
        }
    }

    /** monthly take-home from the last budget quiz (0 if unknown) */
    public double takeHome(String user) {
        return read("users/%s/last_budget_quiz.json".formatted(user)).get("monthlyNet") instanceof Number n ? n.doubleValue() : 0;
    }

    private Map<String, Object> read(String key) {
        try {
            byte[] data = s3.downloadFile(key);
            if (data == null || data.length == 0) return Map.of();
            return json.readValue(data, new TypeReference<Map<String, Object>>() {});
        } catch (Exception e) {
            return Map.of();
        }
    }

    private static Map<String, Double> numbers(Map<?, ?> m) {
        Map<String, Double> out = new LinkedHashMap<>();
        m.forEach((k, v) -> { if (v instanceof Number n) out.put(String.valueOf(k), n.doubleValue()); });
        return out;
    }
}
