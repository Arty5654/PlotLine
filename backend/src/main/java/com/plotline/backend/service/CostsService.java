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
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

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
    public void mergeDated(String username, String type, String dateStr, Map<String, Double> costs, boolean replaceAll) {
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

            // If replaceAll, clear all existing day entries so user's values become the totals
            if (replaceAll) {
                days.clear();
            }

            String dayKey = date.toString();
            @SuppressWarnings("unchecked")
            Map<String, Object> dayCosts = (Map<String, Object>) days.getOrDefault(dayKey, new LinkedHashMap<>());

            // Set day values (simple overwrite, no delta tracking)
            for (var e : costs.entrySet()) {
                String cat = e.getKey();
                double incoming = e.getValue() == null ? 0.0 : round2(e.getValue());
                if (incoming == 0.0) {
                    dayCosts.remove(cat);
                } else {
                    dayCosts.put(cat, incoming);
                }
            }
            days.put(dayKey, dayCosts);

            // Recalculate totals from ALL day entries + adjustments
            Map<String, Object> newTotals = new LinkedHashMap<>();
            for (var dayEntry : days.values()) {
                @SuppressWarnings("unchecked")
                Map<String, Object> dc = (Map<String, Object>) dayEntry;
                for (var ce : dc.entrySet()) {
                    if (ce.getValue() instanceof Number) {
                        double val = ((Number) ce.getValue()).doubleValue();
                        double cur = 0.0;
                        Object existing = newTotals.get(ce.getKey());
                        if (existing instanceof Number) cur = ((Number) existing).doubleValue();
                        newTotals.put(ce.getKey(), round2(cur + val));
                    }
                }
            }
            // Include monthly adjustments (costs not tied to specific days)
            @SuppressWarnings("unchecked")
            Map<String, Object> adj = (Map<String, Object>) period.getOrDefault("adjustments", new LinkedHashMap<>());
            for (var ae : adj.entrySet()) {
                if (ae.getValue() instanceof Number) {
                    double val = ((Number) ae.getValue()).doubleValue();
                    double cur = 0.0;
                    Object existing = newTotals.get(ae.getKey());
                    if (existing instanceof Number) cur = ((Number) existing).doubleValue();
                    newTotals.put(ae.getKey(), round2(cur + val));
                }
            }
            period.put("totals", newTotals);

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

            // ADD costs to day (additive — used by transaction sync)
            for (var e : costs.entrySet()) {
                String cat = e.getKey();
                double addAmount = e.getValue() == null ? 0.0 : round2(e.getValue());
                if (addAmount == 0.0) continue;

                double currentDay = 0.0;
                Object dayVal = dayCosts.get(cat);
                if (dayVal instanceof Number) {
                    currentDay = round2(((Number) dayVal).doubleValue());
                }
                dayCosts.put(cat, round2(currentDay + addAmount));
            }
            days.put(dayKey, dayCosts);

            // Recalculate totals from ALL day entries + adjustments (bulletproof — no drift)
            totals.clear();
            for (var dayEntry : days.values()) {
                @SuppressWarnings("unchecked")
                Map<String, Object> dc = (Map<String, Object>) dayEntry;
                for (var ce : dc.entrySet()) {
                    if (ce.getValue() instanceof Number) {
                        double val = ((Number) ce.getValue()).doubleValue();
                        double cur = 0.0;
                        Object existing = totals.get(ce.getKey());
                        if (existing instanceof Number) cur = ((Number) existing).doubleValue();
                        totals.put(ce.getKey(), round2(cur + val));
                    }
                }
            }
            // Include monthly adjustments (costs not tied to specific days)
            @SuppressWarnings("unchecked")
            Map<String, Object> adj = (Map<String, Object>) period.getOrDefault("adjustments", new LinkedHashMap<>());
            for (var ae : adj.entrySet()) {
                if (ae.getValue() instanceof Number) {
                    double val = ((Number) ae.getValue()).doubleValue();
                    double cur = 0.0;
                    Object existing = totals.get(ae.getKey());
                    if (existing instanceof Number) cur = ((Number) existing).doubleValue();
                    totals.put(ae.getKey(), round2(cur + val));
                }
            }

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

    // ==================== Transaction-level storage ====================

    /**
     * Store a single transaction detail in the monthly period file.
     * Called during Plaid sync to persist individual transaction metadata.
     */
    public void storeTransaction(String username, String dateStr, Map<String, Object> txn) {
        try {
            String normUser = normalize(username);
            LocalDate date = LocalDate.parse(dateStr);
            String periodKey = monthKey(date);
            String key = "users/%s/costs/monthly/%s.json".formatted(normUser, periodKey);

            Map<String, Object> period = loadJsonOrEmpty(key);
            period.putIfAbsent("periodKey", periodKey);
            period.putIfAbsent("days", new LinkedHashMap<String, Object>());
            period.putIfAbsent("totals", new LinkedHashMap<String, Object>());

            @SuppressWarnings("unchecked")
            List<Map<String, Object>> transactions = (List<Map<String, Object>>) period.getOrDefault("transactions", new ArrayList<>());

            // Avoid duplicates by transaction ID
            String txnId = (String) txn.get("id");
            if (txnId != null) {
                transactions.removeIf(t -> txnId.equals(t.get("id")));
            }

            transactions.add(txn);
            period.put("transactions", transactions);
            saveJson(key, period);
        } catch (Exception ex) {
            System.err.println("[CostsService] storeTransaction failed: " + ex.getMessage());
        }
    }

    /**
     * Get all transactions for a given month.
     */
    public List<Map<String, Object>> getTransactions(String username, String monthStr) {
        try {
            String normUser = normalize(username);
            String key = "users/%s/costs/monthly/%s.json".formatted(normUser, monthStr);
            Map<String, Object> period = loadJsonOrEmpty(key);
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> transactions = (List<Map<String, Object>>) period.getOrDefault("transactions", new ArrayList<>());
            return transactions;
        } catch (Exception ex) {
            System.err.println("[CostsService] getTransactions failed: " + ex.getMessage());
            return new ArrayList<>();
        }
    }

    /**
     * Edit a transaction's amount. Updates both the transaction record and the
     * day-level aggregated costs (and totals) in both monthly and weekly files.
     */
    public Map<String, Object> editTransaction(String username, String monthStr, String txnId, double newAmount) {
        try {
            String normUser = normalize(username);
            String key = "users/%s/costs/monthly/%s.json".formatted(normUser, monthStr);
            Map<String, Object> period = loadJsonOrEmpty(key);

            @SuppressWarnings("unchecked")
            List<Map<String, Object>> transactions = (List<Map<String, Object>>) period.getOrDefault("transactions", new ArrayList<>());

            // Find the transaction
            Map<String, Object> target = null;
            for (var t : transactions) {
                if (txnId.equals(t.get("id"))) { target = t; break; }
            }
            if (target == null) return null;

            double oldAmount = target.get("amount") instanceof Number ? ((Number) target.get("amount")).doubleValue() : 0.0;
            String category = (String) target.get("category");
            String dateStr = (String) target.get("date");

            // Save original amount on first edit (for revert)
            if (!target.containsKey("originalAmount")) {
                target.put("originalAmount", oldAmount);
            }
            // Update the transaction record
            target.put("amount", round2(newAmount));
            period.put("transactions", transactions);

            // Compute the delta and apply to day-level costs
            double delta = round2(newAmount - oldAmount);
            if (delta != 0.0 && category != null && dateStr != null) {
                applyDeltaToDays(period, dateStr, category, delta);
                recalcTotals(period);
                saveJson(key, period);

                // Also update weekly file
                Map<String, Double> weeklyDelta = new LinkedHashMap<>();
                weeklyDelta.put(category, delta);
                applyDeltaToWeekly(normUser, dateStr, weeklyDelta);
            } else {
                saveJson(key, period);
            }

            System.out.println("[CostsService] Edited txn " + txnId + " from $" + oldAmount + " to $" + newAmount);
            return target;
        } catch (Exception ex) {
            System.err.println("[CostsService] editTransaction failed: " + ex.getMessage());
            return null;
        }
    }

    /**
     * Move a transaction to a different category.
     * Subtracts the amount from the old category and adds it to the new one
     * in both monthly and weekly day-level costs.
     */
    public Map<String, Object> recategorizeTransaction(String username, String monthStr, String txnId, String newCategory) {
        try {
            String normUser = normalize(username);
            String key = "users/%s/costs/monthly/%s.json".formatted(normUser, monthStr);
            Map<String, Object> period = loadJsonOrEmpty(key);

            @SuppressWarnings("unchecked")
            List<Map<String, Object>> transactions = (List<Map<String, Object>>) period.getOrDefault("transactions", new ArrayList<>());

            Map<String, Object> target = null;
            for (var t : transactions) {
                if (txnId.equals(t.get("id"))) { target = t; break; }
            }
            if (target == null) return null;

            String oldCategory = (String) target.get("category");
            String dateStr = (String) target.get("date");
            double amount = target.get("amount") instanceof Number ? ((Number) target.get("amount")).doubleValue() : 0.0;

            if (oldCategory != null && oldCategory.equals(newCategory)) return target; // no change

            // Update the transaction record
            target.put("category", newCategory);
            period.put("transactions", transactions);

            // Move amount: subtract from old category, add to new category
            if (dateStr != null && amount > 0) {
                if (oldCategory != null) {
                    applyDeltaToDays(period, dateStr, oldCategory, -amount);
                }
                applyDeltaToDays(period, dateStr, newCategory, amount);
                recalcTotals(period);
                saveJson(key, period);

                // Also update weekly file
                Map<String, Double> weeklyDelta = new LinkedHashMap<>();
                if (oldCategory != null) {
                    weeklyDelta.put(oldCategory, -amount);
                }
                weeklyDelta.put(newCategory, weeklyDelta.getOrDefault(newCategory, 0.0) + amount);
                applyDeltaToWeekly(normUser, dateStr, weeklyDelta);
            } else {
                saveJson(key, period);
            }

            System.out.println("[CostsService] Recategorized txn " + txnId + " from " + oldCategory + " to " + newCategory);
            return target;
        } catch (Exception ex) {
            System.err.println("[CostsService] recategorizeTransaction failed: " + ex.getMessage());
            return null;
        }
    }

    /**
     * Revert a transaction to its original amount.
     */
    public Map<String, Object> revertTransaction(String username, String monthStr, String txnId) {
        try {
            String normUser = normalize(username);
            String key = "users/%s/costs/monthly/%s.json".formatted(normUser, monthStr);
            Map<String, Object> period = loadJsonOrEmpty(key);

            @SuppressWarnings("unchecked")
            List<Map<String, Object>> transactions = (List<Map<String, Object>>) period.getOrDefault("transactions", new ArrayList<>());

            Map<String, Object> target = null;
            for (var t : transactions) {
                if (txnId.equals(t.get("id"))) { target = t; break; }
            }
            if (target == null) return null;

            Object origObj = target.get("originalAmount");
            if (origObj == null) return target; // never edited, nothing to revert

            double originalAmount = origObj instanceof Number ? ((Number) origObj).doubleValue() : 0.0;
            double currentAmount = target.get("amount") instanceof Number ? ((Number) target.get("amount")).doubleValue() : 0.0;
            String category = (String) target.get("category");
            String dateStr = (String) target.get("date");

            // Restore original amount and remove the originalAmount marker
            target.put("amount", round2(originalAmount));
            target.remove("originalAmount");
            period.put("transactions", transactions);

            double delta = round2(originalAmount - currentAmount);
            if (delta != 0.0 && category != null && dateStr != null) {
                applyDeltaToDays(period, dateStr, category, delta);
                recalcTotals(period);
                saveJson(key, period);

                Map<String, Double> weeklyDelta = new LinkedHashMap<>();
                weeklyDelta.put(category, delta);
                applyDeltaToWeekly(normUser, dateStr, weeklyDelta);
            } else {
                saveJson(key, period);
            }

            System.out.println("[CostsService] Reverted txn " + txnId + " from $" + currentAmount + " back to $" + originalAmount);
            return target;
        } catch (Exception ex) {
            System.err.println("[CostsService] revertTransaction failed: " + ex.getMessage());
            return null;
        }
    }

    /**
     * Delete a transaction. Removes it from the transactions list and subtracts
     * its amount from the day-level costs in both monthly and weekly files.
     */
    public boolean deleteTransaction(String username, String monthStr, String txnId) {
        try {
            String normUser = normalize(username);
            String key = "users/%s/costs/monthly/%s.json".formatted(normUser, monthStr);
            Map<String, Object> period = loadJsonOrEmpty(key);

            @SuppressWarnings("unchecked")
            List<Map<String, Object>> transactions = (List<Map<String, Object>>) period.getOrDefault("transactions", new ArrayList<>());

            // Find and remove
            Map<String, Object> target = null;
            for (var t : transactions) {
                if (txnId.equals(t.get("id"))) { target = t; break; }
            }
            if (target == null) return false;

            double amount = target.get("amount") instanceof Number ? ((Number) target.get("amount")).doubleValue() : 0.0;
            String category = (String) target.get("category");
            String dateStr = (String) target.get("date");

            transactions.remove(target);
            period.put("transactions", transactions);

            // Subtract from day-level costs
            if (amount > 0 && category != null && dateStr != null) {
                applyDeltaToDays(period, dateStr, category, -amount);
                recalcTotals(period);
                saveJson(key, period);

                // Also update weekly file
                Map<String, Double> weeklyDelta = new LinkedHashMap<>();
                weeklyDelta.put(category, -amount);
                applyDeltaToWeekly(normUser, dateStr, weeklyDelta);
            } else {
                saveJson(key, period);
            }

            System.out.println("[CostsService] Deleted txn " + txnId + " ($" + amount + " " + category + ")");
            return true;
        } catch (Exception ex) {
            System.err.println("[CostsService] deleteTransaction failed: " + ex.getMessage());
            return false;
        }
    }

    /** Apply a delta to a specific day+category in the period's days map. */
    private void applyDeltaToDays(Map<String, Object> period, String dateStr, String category, double delta) {
        @SuppressWarnings("unchecked")
        Map<String, Object> days = (Map<String, Object>) period.getOrDefault("days", new LinkedHashMap<>());
        @SuppressWarnings("unchecked")
        Map<String, Object> dayCosts = (Map<String, Object>) days.getOrDefault(dateStr, new LinkedHashMap<>());

        double current = 0.0;
        Object val = dayCosts.get(category);
        if (val instanceof Number) current = ((Number) val).doubleValue();

        double newVal = round2(Math.max(0, current + delta));
        if (newVal == 0.0) {
            dayCosts.remove(category);
        } else {
            dayCosts.put(category, newVal);
        }

        if (dayCosts.isEmpty()) {
            days.remove(dateStr);
        } else {
            days.put(dateStr, dayCosts);
        }
        period.put("days", days);
    }

    /** Recalculate totals from days + adjustments. */
    private void recalcTotals(Map<String, Object> period) {
        @SuppressWarnings("unchecked")
        Map<String, Object> days = (Map<String, Object>) period.getOrDefault("days", new LinkedHashMap<>());
        Map<String, Object> newTotals = new LinkedHashMap<>();
        for (var dayEntry : days.values()) {
            @SuppressWarnings("unchecked")
            Map<String, Object> dc = (Map<String, Object>) dayEntry;
            for (var ce : dc.entrySet()) {
                if (ce.getValue() instanceof Number) {
                    double val = ((Number) ce.getValue()).doubleValue();
                    double cur = 0.0;
                    Object existing = newTotals.get(ce.getKey());
                    if (existing instanceof Number) cur = ((Number) existing).doubleValue();
                    newTotals.put(ce.getKey(), round2(cur + val));
                }
            }
        }
        @SuppressWarnings("unchecked")
        Map<String, Object> adj = (Map<String, Object>) period.getOrDefault("adjustments", new LinkedHashMap<>());
        for (var ae : adj.entrySet()) {
            if (ae.getValue() instanceof Number) {
                double val = ((Number) ae.getValue()).doubleValue();
                double cur = 0.0;
                Object existing = newTotals.get(ae.getKey());
                if (existing instanceof Number) cur = ((Number) existing).doubleValue();
                newTotals.put(ae.getKey(), round2(cur + val));
            }
        }
        period.put("totals", newTotals);
    }

    /** Apply a delta to the weekly period file for the given date. */
    private void applyDeltaToWeekly(String normUser, String dateStr, Map<String, Double> deltas) {
        try {
            LocalDate date = LocalDate.parse(dateStr);
            String wk = weekKey(date);
            String key = "users/%s/costs/weekly/%s.json".formatted(normUser, wk);
            Map<String, Object> period = loadJsonOrEmpty(key);

            period.putIfAbsent("periodKey", wk);
            period.putIfAbsent("days", new LinkedHashMap<String, Object>());
            period.putIfAbsent("totals", new LinkedHashMap<String, Object>());

            for (var e : deltas.entrySet()) {
                applyDeltaToDays(period, dateStr, e.getKey(), e.getValue());
            }
            recalcTotals(period);

            // Store start/end
            LocalDate start = date.minusDays((date.getDayOfWeek().getValue() % 7));
            LocalDate end = start.plusDays(6);
            period.put("start", start.toString());
            period.put("end", end.toString());

            saveJson(key, period);
        } catch (Exception ex) {
            System.err.println("[CostsService] applyDeltaToWeekly failed: " + ex.getMessage());
        }
    }

    /**
     * Set desired monthly totals. Uses two strategies:
     * - Monthly-only costs (no daily entries): stored in "adjustments" field, excluded from weekly charts.
     * - Overrides on synced categories (have daily entries): written as correction to days["1st"],
     *   so the weekly chart also reflects the user's intended total.
     */
    public Map<String, Object> setMonthlyTotals(String username, String monthStr, Map<String, Double> desiredTotals) {
        try {
            String normUser = normalize(username);
            String key = "users/%s/costs/monthly/%s.json".formatted(normUser, monthStr);

            Map<String, Object> period = loadJsonOrEmpty(key);
            period.putIfAbsent("periodKey", monthStr);
            period.putIfAbsent("days", new LinkedHashMap<String, Object>());

            @SuppressWarnings("unchecked")
            Map<String, Object> days = (Map<String, Object>) period.get("days");

            YearMonth ym = YearMonth.parse(monthStr);
            String firstDay = ym.atDay(1).toString();

            // Step 1: Clear any old adjustment entries from the 1st of month.
            // The old code stored monthly adjustments in days["1st"]. We need to
            // clean those out before recomputing, so they don't pollute the weekly chart.
            @SuppressWarnings("unchecked")
            Map<String, Object> firstDayCosts = (Map<String, Object>) days.getOrDefault(firstDay, new LinkedHashMap<>());

            // Find categories that appear on days OTHER than the 1st (real synced/daily entries)
            Set<String> catsOnOtherDays = new HashSet<>();
            for (var entry : days.entrySet()) {
                if (entry.getKey().equals(firstDay)) continue;
                @SuppressWarnings("unchecked")
                Map<String, Object> dc = (Map<String, Object>) entry.getValue();
                catsOnOtherDays.addAll(dc.keySet());
            }

            // Remove categories from the 1st that don't appear on any other day
            // (these are old adjustment entries, not real transactions)
            firstDayCosts.keySet().removeIf(cat -> !catsOnOtherDays.contains(cat));
            if (firstDayCosts.isEmpty()) {
                days.remove(firstDay);
            }

            // Step 2: Compute sum of all remaining day entries per category
            Map<String, Double> daySum = new LinkedHashMap<>();
            for (var dayEntry : days.values()) {
                @SuppressWarnings("unchecked")
                Map<String, Object> dc = (Map<String, Object>) dayEntry;
                for (var ce : dc.entrySet()) {
                    if (ce.getValue() instanceof Number) {
                        daySum.merge(ce.getKey(), ((Number) ce.getValue()).doubleValue(), Double::sum);
                    }
                }
            }

            // Step 3: For each category, decide where to put the correction
            Set<String> allCats = new HashSet<>(desiredTotals.keySet());
            allCats.addAll(daySum.keySet());
            @SuppressWarnings("unchecked")
            Map<String, Object> existingAdj = (Map<String, Object>) period.getOrDefault("adjustments", new LinkedHashMap<>());
            allCats.addAll(existingAdj.keySet());

            Map<String, Object> adjustments = new LinkedHashMap<>();
            Map<String, Object> firstDayUpdates = new LinkedHashMap<>(); // corrections for synced categories

            for (String cat : allCats) {
                double desired = desiredTotals.getOrDefault(cat, 0.0);
                double fromDays = round2(daySum.getOrDefault(cat, 0.0));
                double diff = round2(desired - fromDays);

                if (diff == 0.0) continue; // no correction needed

                boolean hasDailyEntries = catsOnOtherDays.contains(cat);

                if (hasDailyEntries) {
                    // Category has synced/daily entries → write correction to days["1st"]
                    // so the weekly chart reflects the override
                    firstDayUpdates.put(cat, diff);
                } else {
                    // Monthly-only cost (no daily entries) → store in adjustments
                    // so it doesn't appear in the weekly chart
                    adjustments.put(cat, diff);
                }
            }

            // Step 4: Apply first-day corrections to the days map
            if (!firstDayUpdates.isEmpty()) {
                @SuppressWarnings("unchecked")
                Map<String, Object> fdc = (Map<String, Object>) days.getOrDefault(firstDay, new LinkedHashMap<>());
                for (var e : firstDayUpdates.entrySet()) {
                    double val = ((Number) e.getValue()).doubleValue();
                    double existing = 0.0;
                    Object cur = fdc.get(e.getKey());
                    if (cur instanceof Number) existing = ((Number) cur).doubleValue();
                    double newVal = round2(existing + val);
                    if (newVal == 0.0) {
                        fdc.remove(e.getKey());
                    } else {
                        fdc.put(e.getKey(), newVal);
                    }
                }
                if (!fdc.isEmpty()) {
                    days.put(firstDay, fdc);
                } else {
                    days.remove(firstDay);
                }
            }

            period.put("adjustments", adjustments);

            // Step 5: Recompute totals = sum(days) + adjustments
            Map<String, Object> newTotals = new LinkedHashMap<>();
            for (var dayEntry : days.values()) {
                @SuppressWarnings("unchecked")
                Map<String, Object> dc = (Map<String, Object>) dayEntry;
                for (var ce : dc.entrySet()) {
                    if (ce.getValue() instanceof Number) {
                        double val = ((Number) ce.getValue()).doubleValue();
                        double cur = 0.0;
                        Object existing = newTotals.get(ce.getKey());
                        if (existing instanceof Number) cur = ((Number) existing).doubleValue();
                        newTotals.put(ce.getKey(), round2(cur + val));
                    }
                }
            }
            for (var ae : adjustments.entrySet()) {
                if (ae.getValue() instanceof Number) {
                    double val = ((Number) ae.getValue()).doubleValue();
                    double cur = 0.0;
                    Object existing = newTotals.get(ae.getKey());
                    if (existing instanceof Number) cur = ((Number) existing).doubleValue();
                    double total = round2(cur + val);
                    if (total != 0.0) {
                        newTotals.put(ae.getKey(), total);
                    }
                }
            }
            // Preserve all categories the user explicitly sent (even $0 ones)
            // so they persist in the UI after reload
            for (String cat : desiredTotals.keySet()) {
                newTotals.putIfAbsent(cat, 0.0);
            }

            period.put("totals", newTotals);

            // Store start/end
            period.put("start", ym.atDay(1).toString());
            period.put("end", ym.atEndOfMonth().toString());

            saveJson(key, period);
            System.out.println("[CostsService] Set monthly totals for " + normUser + " month=" + monthStr + ": " + desiredTotals);
            return period;

        } catch (Exception ex) {
            System.err.println("[CostsService] setMonthlyTotals failed: " + ex.getMessage());
            ex.printStackTrace();
            return null;
        }
    }
}
