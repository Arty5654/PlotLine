package com.plotline.backend.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.temporal.WeekFields;
import java.util.LinkedHashMap;
import java.util.Map;

import static com.plotline.backend.util.UsernameUtils.normalize;

@Service
public class CostsService {

    @Autowired
    private S3Service s3Service;

    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * Merge costs for a specific date into the weekly/monthly period file.
     * This method is called directly (no HTTP) to avoid self-call issues on Fly.io.
     */
    public void mergeDated(String username, String type, String dateStr, Map<String, Double> costs) {
        try {
            String normUser = normalize(username);
            LocalDate date = LocalDate.parse(dateStr);
            String periodKey = "weekly".equalsIgnoreCase(type) ? weekKey(date) : monthKey(date);
            String key = "users/%s/costs/%s/%s.json".formatted(normUser, type.toLowerCase(), periodKey);

            Map<String, Object> period = loadJsonOrEmpty(key);

            // Initialize fields if new
            period.putIfAbsent("periodKey", periodKey);
            period.putIfAbsent("days", new LinkedHashMap<String, Object>());
            period.putIfAbsent("totals", new LinkedHashMap<String, Object>());

            @SuppressWarnings("unchecked")
            Map<String, Object> days = (Map<String, Object>) period.get("days");
            @SuppressWarnings("unchecked")
            Map<String, Object> totals = (Map<String, Object>) period.get("totals");

            String dayKey = date.toString();
            @SuppressWarnings("unchecked")
            Map<String, Object> dayCosts = (Map<String, Object>) days.getOrDefault(dayKey, new LinkedHashMap<>());

            // Merge costs
            for (var e : costs.entrySet()) {
                String cat = e.getKey();
                double incoming = e.getValue() == null ? 0.0 : round2(e.getValue());

                // Get previous value for this day
                double prev = 0.0;
                Object prevVal = dayCosts.get(cat);
                if (prevVal instanceof Number) {
                    prev = round2(((Number) prevVal).doubleValue());
                }
                double delta = round2(incoming - prev);

                if (incoming == 0.0) {
                    // Treat zero as "clear this category for the day"
                    if (prev != 0.0) {
                        dayCosts.remove(cat);
                        Object totalVal = totals.get(cat);
                        double currentTotal = (totalVal instanceof Number) ? ((Number) totalVal).doubleValue() : 0.0;
                        totals.put(cat, round2(currentTotal - prev));
                    }
                } else {
                    dayCosts.put(cat, incoming);
                    Object totalVal = totals.get(cat);
                    double currentTotal = (totalVal instanceof Number) ? ((Number) totalVal).doubleValue() : 0.0;
                    totals.put(cat, round2(currentTotal + delta));
                }
            }

            days.put(dayKey, dayCosts);

            // Store start/end for weekly/monthly
            if ("weekly".equalsIgnoreCase(type)) {
                LocalDate start = date.minusDays((date.getDayOfWeek().getValue() % 7));
                LocalDate end = start.plusDays(6);
                period.put("start", start.toString());
                period.put("end", end.toString());
            } else {
                YearMonth ym = YearMonth.from(date);
                period.put("start", ym.atDay(1).toString());
                period.put("end", ym.atEndOfMonth().toString());
            }

            saveJson(key, period);
            System.out.println("[CostsService] Merged " + type + " costs for " + normUser + " on " + dateStr + ": " + costs);

        } catch (Exception ex) {
            System.err.println("[CostsService] mergeDated failed: " + ex.getMessage());
            ex.printStackTrace();
        }
    }

    private String weekKey(LocalDate date) {
        DayOfWeek dow = date.getDayOfWeek();
        LocalDate start = date.minusDays((dow.getValue() % 7)); // Sunday = 0
        int weekOfYear = start.get(WeekFields.SUNDAY_START.weekOfWeekBasedYear());
        int year = start.get(WeekFields.SUNDAY_START.weekBasedYear());
        return "%04d-W%02d".formatted(year, weekOfYear);
    }

    private String monthKey(LocalDate date) {
        return "%04d-%02d".formatted(date.getYear(), date.getMonthValue());
    }

    private Map<String, Object> loadJsonOrEmpty(String key) {
        try {
            byte[] raw = s3Service.downloadFile(key);
            return objectMapper.readValue(raw, new TypeReference<Map<String, Object>>() {});
        } catch (Exception e) {
            return new LinkedHashMap<>();
        }
    }

    private void saveJson(String key, Map<String, Object> payload) throws Exception {
        String json = objectMapper.writeValueAsString(payload);
        try (var in = new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8))) {
            s3Service.uploadFile(key, in, json.length());
        }
    }

    private static double round2(double v) {
        return Math.round(v * 100.0) / 100.0;
    }

    /**
     * ADD costs for a specific date (used by manual assignment).
     * Unlike mergeDated which SETs values, this method ADDS to existing values.
     */
    public void addDated(String username, String type, String dateStr, Map<String, Double> costs) {
        try {
            String normUser = normalize(username);
            LocalDate date = LocalDate.parse(dateStr);
            String periodKey = "weekly".equalsIgnoreCase(type) ? weekKey(date) : monthKey(date);
            String key = "users/%s/costs/%s/%s.json".formatted(normUser, type.toLowerCase(), periodKey);

            Map<String, Object> period = loadJsonOrEmpty(key);

            // Initialize fields if new
            period.putIfAbsent("periodKey", periodKey);
            period.putIfAbsent("days", new LinkedHashMap<String, Object>());
            period.putIfAbsent("totals", new LinkedHashMap<String, Object>());

            @SuppressWarnings("unchecked")
            Map<String, Object> days = (Map<String, Object>) period.get("days");
            @SuppressWarnings("unchecked")
            Map<String, Object> totals = (Map<String, Object>) period.get("totals");

            String dayKey = date.toString();
            @SuppressWarnings("unchecked")
            Map<String, Object> dayCosts = (Map<String, Object>) days.getOrDefault(dayKey, new LinkedHashMap<>());

            // ADD costs (not set)
            for (var e : costs.entrySet()) {
                String cat = e.getKey();
                double addAmount = e.getValue() == null ? 0.0 : round2(e.getValue());

                if (addAmount == 0.0) continue;

                // Add to day's costs
                double currentDay = 0.0;
                Object dayVal = dayCosts.get(cat);
                if (dayVal instanceof Number) {
                    currentDay = round2(((Number) dayVal).doubleValue());
                }
                dayCosts.put(cat, round2(currentDay + addAmount));

                // Add to totals
                double currentTotal = 0.0;
                Object totalVal = totals.get(cat);
                if (totalVal instanceof Number) {
                    currentTotal = round2(((Number) totalVal).doubleValue());
                }
                totals.put(cat, round2(currentTotal + addAmount));
            }

            days.put(dayKey, dayCosts);

            // Store start/end for weekly/monthly
            if ("weekly".equalsIgnoreCase(type)) {
                LocalDate start = date.minusDays((date.getDayOfWeek().getValue() % 7));
                LocalDate end = start.plusDays(6);
                period.put("start", start.toString());
                period.put("end", end.toString());
            } else {
                YearMonth ym = YearMonth.from(date);
                period.put("start", ym.atDay(1).toString());
                period.put("end", ym.atEndOfMonth().toString());
            }

            saveJson(key, period);
            System.out.println("[CostsService] Added " + type + " costs for " + normUser + " on " + dateStr + ": " + costs);

        } catch (Exception ex) {
            System.err.println("[CostsService] addDated failed: " + ex.getMessage());
            ex.printStackTrace();
        }
    }
}
