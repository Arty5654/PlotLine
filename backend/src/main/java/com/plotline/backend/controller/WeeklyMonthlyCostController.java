package com.plotline.backend.controller;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.WeeklyMonthlyCostRequest;
import com.plotline.backend.service.S3Service;
import com.plotline.backend.service.OpenAIService;
import static com.plotline.backend.util.UsernameUtils.normalize;

import io.jsonwebtoken.io.IOException;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.http.MediaType;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.temporal.ChronoField;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import java.util.Objects;
import java.util.LinkedHashMap;
import java.util.HashSet;
import java.util.Set;
import java.util.Iterator;

import java.time.DayOfWeek;
import java.time.YearMonth;
import java.time.temporal.WeekFields;
import java.math.BigDecimal;
import java.math.RoundingMode;


@RestController
@RequestMapping("/api/costs")
public class WeeklyMonthlyCostController {

    @Autowired
    private S3Service s3Service;

    @Autowired
    private OpenAIService openAIService;

    @Autowired
    private com.plotline.backend.service.UserProfileService userProfileService;

    @Autowired
    private com.plotline.backend.service.CostsService costsService;

    @PostMapping
    public ResponseEntity<String> saveWeeklyMonthlyCosts(@RequestBody WeeklyMonthlyCostRequest request) {
        try {
            String normUser = normalize(request.getUsername());
            // Ensure all costs are stored as Double
            //request.getCosts().replaceAll((k, v) -> Double.valueOf(String.valueOf(v)));
 
            // Convert request object to JSON string
            String jsonData = new ObjectMapper().writeValueAsString(request);

            // Convert string to InputStream for S3 upload
            ByteArrayInputStream inputStream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));

            // Generate a unique S3 key per user
            String key = "users/" + normUser + "/" + request.getType() + "_costs.json";

            // Upload the file to S3 using S3Service
            //s3Service.uploadFile(key, inputStream, jsonData.length());
            //updateWeeklyCosts(request.getUsername(), request.getCosts());
            overwriteCosts(normUser, request.getType(), request.getCosts());

            return ResponseEntity.ok("Weekly/Monthly costs saved successfully.");
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error saving data: " + e.getMessage());
        }
    }

    @GetMapping("/{username}/{type}")
    public ResponseEntity<String> getWeeklyMonthlyCosts(@PathVariable String username, @PathVariable String type) {
        String normUser = normalize(username);
        try {
            // Determine current week or month
            //int period = determinePeriod(type);

            // Generate the key dynamically
            String key = "users/" + normUser + "/" + type + "_costs" + ".json";

            // Fetch data from S3
            byte[] fileData = s3Service.downloadFile(key);
            String jsonData = new String(fileData, StandardCharsets.UTF_8);

            return ResponseEntity.ok(jsonData);
        } catch (Exception e) {
            // Instead of returning `{}`, return a valid empty response that matches the expected format
            String emptyJson = "{ \"username\": \"" + normUser + "\", \"type\": \"" + type + "\", \"costs\": {} }";
            return ResponseEntity.ok(emptyJson);
        }
    }


    @DeleteMapping("/{username}/{type}")
    public ResponseEntity<String> deleteWeeklyMonthlyCosts(@PathVariable String username, @PathVariable String type) {
        try {
            String normUser = normalize(username);
            // Generate key to delete
            String key = "users/" + normUser + "/" + type + "_costs.json";

            // Delete file from S3
            s3Service.deleteFile(key);

            return ResponseEntity.ok("Deleted " + type + " costs for " + username);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error deleting data: " + e.getMessage());
        }
    }

    @PostMapping("/upload-receipt")
    public ResponseEntity<Map<String, Object>> handleReceiptUpload(
            @RequestParam("image") MultipartFile image,
            @RequestParam("username") String username,
            @RequestParam(value = "date", required = false) String dateStr) {
        try {
            String normUser = normalize(username);

            // Convert image to base64 for GPT-4o Vision
            byte[] imageBytes = image.getBytes();
            String base64Image = java.util.Base64.getEncoder().encodeToString(imageBytes);

            System.out.println("Sending receipt image to GPT-4o Vision (size: " + imageBytes.length + " bytes)");

            // Use GPT-4o Vision to analyze the receipt directly (much more accurate than OCR)
            String response = openAIService.analyzeReceiptFromImage(base64Image);
            System.out.println("GPT-4o Vision Response:\n" + response);

            // Clean up response to parse (remove markdown code blocks if present)
            String cleanedJson = response
                .replaceAll("(?s)```json\\s*", "")  // remove ```json
                .replaceAll("(?s)```", "")          // remove closing ```
                .trim();

            // Parse the JSON result
            Map<String, Object> result = new ObjectMapper().readValue(cleanedJson, new TypeReference<>() {});

            // Check for error in response
            if (result.containsKey("error")) {
                return ResponseEntity.status(500).body(result);
            }

            // Extract numeric values for updating costs
            Map<String, Double> parsed = result.entrySet().stream()
                    .filter(e -> e.getValue() instanceof Number)
                    .map(e -> Map.entry(e.getKey(), ((Number) e.getValue()).doubleValue()))
                    .filter(e -> e.getValue() > 0) // prevent 0 values from being passed into updates
                    .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));

            // Update both weekly and monthly dated costs (use client date if provided)
            LocalDate today = (dateStr != null && !dateStr.isBlank())
                ? LocalDate.parse(dateStr)
                : LocalDate.now();
            updateDatedCosts(normUser, "weekly", today, parsed);
            updateDatedCosts(normUser, "monthly", today, parsed);

            System.out.println("Receipt processed successfully: " + result);

            // Return the parsed costs so iOS can use them for undo/edit
            Map<String, Object> responseWithMeta = new HashMap<>(result);
            responseWithMeta.put("_addedCosts", parsed);
            responseWithMeta.put("_date", today.toString());
            return ResponseEntity.ok(responseWithMeta);

        } catch (Exception e) {
            e.printStackTrace();
            Map<String, Object> error = new HashMap<>();
            error.put("error", e.getMessage());
            return ResponseEntity.status(500).body(error);
        }
    }

    private void overwriteCosts(String username, String type,
                            Map<String, Double> newCosts) throws Exception {
        String normUser = normalize(username);
        Map<String, Object> data = Map.of(
            "username", normUser,
            "type",     type,
            "costs",    newCosts
        );

        String key = "users/" + normUser + "/" + type + "_costs.json";
        String json = new ObjectMapper().writeValueAsString(data);
        s3Service.uploadFile(key,
            new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8)),
            json.length());
    }


    private void mergeCosts(String username,
        String type,
        Map<String, Double> delta) throws Exception {

        String normUser = normalize(username);
        String key = "users/" + normUser + "/" + type + "_costs.json";

        // 1.  Load existing file (or create an empty shell)
        Map<String,Object> data;
        try {
        byte[] raw = s3Service.downloadFile(key);
        data = new ObjectMapper().readValue(raw, new TypeReference<>() {});
        } catch (Exception e) {           // file doesn’t exist yet
        data = new HashMap<>();
        data.put("username", normUser);
        data.put("type",     type);
        data.put("costs",    new HashMap<String,Double>());
        }

        // 2.  Merge the delta
        @SuppressWarnings("unchecked")
        Map<String,Double> costs = (Map<String,Double>) data.get("costs");
        for (var entry : delta.entrySet()) {
        String  cat   = entry.getKey();
        double  add   = entry.getValue();
        costs.put(cat, costs.getOrDefault(cat, 0.0) + add);
        }
        data.put("costs", costs);

        // 3.  Save back to S3
        String json = new ObjectMapper().writeValueAsString(data);
        s3Service.uploadFile(
        key,
        new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8)),
        json.length()
        );
        }

        /** Convenience wrapper kept for receipt-scanner code */
        private void updateWeeklyCosts(String username, Map<String,Double> delta){
        try { mergeCosts(normalize(username), "weekly", delta); }
        catch (Exception e){                       // you can log if you like
        System.err.println("merge error: "+e.getMessage());
        }
    }

    /**
     * Update dated costs (weekly or monthly) by adding delta values.
     * This creates the category if it doesn't exist.
     */
    private void updateDatedCosts(String username, String type, LocalDate date, Map<String, Double> delta) {
        try {
            String periodKey = "weekly".equalsIgnoreCase(type) ? weekKey(date) : monthKey(date);
            String key = "users/%s/costs/%s/%s.json".formatted(username, type.toLowerCase(), periodKey);

            System.out.println("[DEBUG] updateDatedCosts: Loading from S3 key: " + key);
            Map<String, Object> period = loadJsonOrEmpty(key);
            System.out.println("[DEBUG] Loaded period: " + period);

            // Initialize fields if new
            period.putIfAbsent("periodKey", periodKey);
            period.putIfAbsent("days", new LinkedHashMap<String, Object>());
            period.putIfAbsent("totals", new LinkedHashMap<String, Object>());

            @SuppressWarnings("unchecked")
            Map<String, Object> days = (Map<String, Object>) period.get("days");
            @SuppressWarnings("unchecked")
            Map<String, Object> totals = (Map<String, Object>) period.get("totals");

            System.out.println("[DEBUG] Current totals before update: " + totals);

            String dayKey = date.toString();
            @SuppressWarnings("unchecked")
            Map<String, Object> dayCostsRaw = (Map<String, Object>) days.getOrDefault(dayKey, new LinkedHashMap<>());

            System.out.println("[DEBUG] Current day costs for " + dayKey + ": " + dayCostsRaw);
            System.out.println("[DEBUG] Delta to add: " + delta);

            // Add delta to day's costs
            for (var entry : delta.entrySet()) {
                String cat = entry.getKey();
                double addAmount = round2(entry.getValue());

                double currentDay = 0.0;
                Object dayVal = dayCostsRaw.get(cat);
                if (dayVal instanceof Number) {
                    currentDay = round2(((Number) dayVal).doubleValue());
                }
                dayCostsRaw.put(cat, round2(currentDay + addAmount));
            }
            days.put(dayKey, dayCostsRaw);

            // Recalculate totals from ALL day entries (bulletproof — no drift)
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
            System.out.println("Updated " + type + " costs for " + username + ": " + delta);
        } catch (Exception e) {
            System.err.println("updateDatedCosts error: " + e.getMessage());
            e.printStackTrace();
        }
    }

    @PostMapping("/merge")
        public ResponseEntity<String> merge(@RequestBody WeeklyMonthlyCostRequest req){
        try {
        mergeCosts(normalize(req.getUsername()), req.getType(), req.getCosts());
        return ResponseEntity.ok("Merged successfully");
        } catch (Exception e){
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
        .body("Error merging: "+e.getMessage());
        }
    }

    /**
     * Add costs to dated file (for edit flow). This ADDS to existing values, not sets.
     */
    @PostMapping(value = "/add-dated", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> addDatedCosts(@RequestBody Map<String, Object> body) {
        try {
            String username = normalize(String.valueOf(body.get("username")));
            String type = String.valueOf(body.get("type")); // weekly|monthly
            String dateStr = String.valueOf(body.getOrDefault("date", LocalDate.now().toString()));
            @SuppressWarnings("unchecked")
            Map<String, Number> costs = (Map<String, Number>) body.get("costs");

            LocalDate date = LocalDate.parse(dateStr);

            // Convert to double map
            Map<String, Double> delta = new HashMap<>();
            for (var e : costs.entrySet()) {
                double val = e.getValue() == null ? 0.0 : e.getValue().doubleValue();
                if (val > 0) {
                    delta.put(e.getKey(), val);
                }
            }

            // Use updateDatedCosts which ADDS to existing values
            updateDatedCosts(username, type, date, delta);

            return ResponseEntity.ok(Map.of("success", true, "added", delta));
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Undo/subtract costs from dated weekly AND monthly costs.
     * Used by receipt undo functionality.
     */
    @PostMapping("/undo-receipt")
    public ResponseEntity<?> undoReceiptCosts(@RequestBody Map<String, Object> body) {
        try {
            String username = normalize(String.valueOf(body.get("username")));
            String dateStr = String.valueOf(body.getOrDefault("date", LocalDate.now().toString()));
            @SuppressWarnings("unchecked")
            Map<String, Number> costs = (Map<String, Number>) body.get("costs");

            LocalDate date = LocalDate.parse(dateStr);

            // Convert to double map with negative values for subtraction
            Map<String, Double> negativeDelta = new HashMap<>();
            for (var e : costs.entrySet()) {
                double val = e.getValue() == null ? 0.0 : e.getValue().doubleValue();
                negativeDelta.put(e.getKey(), -val);
            }

            // Subtract from both weekly and monthly
            subtractDatedCosts(username, "weekly", date, negativeDelta);
            subtractDatedCosts(username, "monthly", date, negativeDelta);

            return ResponseEntity.ok(Map.of("success", true, "message", "Receipt costs undone"));
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Subtract costs from dated file (for undo). Prevents negative values.
     */
    private void subtractDatedCosts(String username, String type, LocalDate date, Map<String, Double> negativeDelta) {
        try {
            String periodKey = "weekly".equalsIgnoreCase(type) ? weekKey(date) : monthKey(date);
            String key = "users/%s/costs/%s/%s.json".formatted(username, type.toLowerCase(), periodKey);

            Map<String, Object> period = loadJsonOrEmpty(key);
            if (period.isEmpty()) return; // Nothing to subtract from

            @SuppressWarnings("unchecked")
            Map<String, Object> days = (Map<String, Object>) period.get("days");
            @SuppressWarnings("unchecked")
            Map<String, Object> totals = (Map<String, Object>) period.get("totals");

            if (days == null || totals == null) return;

            String dayKey = date.toString();
            @SuppressWarnings("unchecked")
            Map<String, Object> dayCosts = (Map<String, Object>) days.getOrDefault(dayKey, new LinkedHashMap<>());

            for (var entry : negativeDelta.entrySet()) {
                String cat = entry.getKey();
                double subtractAmount = Math.abs(entry.getValue());

                double currentDay = 0.0;
                Object dayVal = dayCosts.get(cat);
                if (dayVal instanceof Number) {
                    currentDay = ((Number) dayVal).doubleValue();
                }
                double newDay = Math.max(0, round2(currentDay - subtractAmount));
                if (newDay == 0) {
                    dayCosts.remove(cat);
                } else {
                    dayCosts.put(cat, newDay);
                }
            }
            days.put(dayKey, dayCosts);

            // Recalculate totals from ALL day entries
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

            saveJson(key, period);
            System.out.println("Subtracted " + type + " costs for " + username + ": " + negativeDelta);
        } catch (Exception e) {
            System.err.println("subtractDatedCosts error: " + e.getMessage());
        }
    }

    // Calander format for weekly costs
    private static String weekKey(LocalDate date) {
        // Sunday-based week example
        DayOfWeek dow = date.getDayOfWeek();
        LocalDate start = date.minusDays((dow.getValue() % 7)); // Sunday = 0
        int weekOfYear = start.get(WeekFields.SUNDAY_START.weekOfWeekBasedYear());
        int year = start.get(WeekFields.SUNDAY_START.weekBasedYear());
        return "%04d-W%02d".formatted(year, weekOfYear);
    }

    private static String monthKey(LocalDate date) {
        return "%04d-%02d".formatted(date.getYear(), date.getMonthValue());
    }

    // ---------- GET for WEEKLY ----------
    @GetMapping("/weekly/{username}")
    public ResponseEntity<?> getWeeklyPeriod(
            @PathVariable String username,
            @RequestParam(name="week_start") String weekStart // YYYY-MM-DD (Sunday of that week)
    ) {
        try {
            String normUser = normalize(username);
            LocalDate start = LocalDate.parse(weekStart);
            // normalize to the server’s concept of week, then build the key
            WeekFields wf = WeekFields.SUNDAY_START;
            String keyPart = weekKey(start);
            String s3Key = "users/%s/costs/weekly/%s.json".formatted(normUser, keyPart);

            Map<String,Object> period = loadJsonOrEmpty(s3Key);
            // If empty, seed a minimal object so the client can render
            period.putIfAbsent("periodKey", keyPart);
            period.putIfAbsent("start", start.toString());
            period.putIfAbsent("end", start.plusDays(6).toString());
            period.putIfAbsent("days", new LinkedHashMap<String, Map<String, Double>>());
            period.putIfAbsent("totals", new LinkedHashMap<String, Double>());

            return ResponseEntity.ok(period);
        } catch (Exception e) {
            return ResponseEntity.status(500).body("weekly fetch failed: " + e.getMessage());
        }
    }

    // ---------- GET for MONTHLY (optional but handy) ----------
    @GetMapping("/monthly/{username}")
    public ResponseEntity<?> getMonthlyPeriod(
            @PathVariable String username,
            @RequestParam(name="month") String month // "YYYY-MM"
    ) {
        try {
            String normUser = normalize(username);
            YearMonth ym = YearMonth.parse(month);
            String keyPart = String.format("%04d-%02d", ym.getYear(), ym.getMonthValue());
            String s3Key = "users/%s/costs/monthly/%s.json".formatted(normUser, keyPart);

            Map<String,Object> period = loadJsonOrEmpty(s3Key);
            period.putIfAbsent("periodKey", keyPart);
            period.putIfAbsent("start", ym.atDay(1).toString());
            period.putIfAbsent("end", ym.atEndOfMonth().toString());
            period.putIfAbsent("days", new LinkedHashMap<String, Map<String, Double>>());
            period.putIfAbsent("totals", new LinkedHashMap<String, Double>());

            // Include fixed costs so the client can display them
            List<Map<String, Object>> fixedCosts = loadFixedCosts(normUser);
            period.put("fixedCosts", fixedCosts);

            // Merge fixed costs into totals so budget summary, feedback, and charts reflect them
            @SuppressWarnings("unchecked")
            Map<String, Object> totals = (Map<String, Object>) period.get("totals");
            for (var fc : fixedCosts) {
                String cat = String.valueOf(fc.get("category"));
                double amt = fc.get("amount") instanceof Number ? ((Number) fc.get("amount")).doubleValue() : 0.0;
                if (amt > 0) {
                    double cur = 0.0;
                    Object existing = totals.get(cat);
                    if (existing instanceof Number) cur = ((Number) existing).doubleValue();
                    totals.put(cat, round2(cur + amt));
                }
            }

            return ResponseEntity.ok(period);
        } catch (Exception e) {
            return ResponseEntity.status(500).body("monthly fetch failed: " + e.getMessage());
        }
    }

    @PostMapping(
    value = "/merge-dated",
    consumes = MediaType.APPLICATION_JSON_VALUE,
    produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<?> mergeDatedCosts(@RequestBody Map<String, Object> body) {
        try {
            String username = normalize(String.valueOf(body.get("username")));
            String type = String.valueOf(body.get("type")); // weekly|monthly
            String dateStr = String.valueOf(body.getOrDefault("date", LocalDate.now().toString()));
            @SuppressWarnings("unchecked")
            Map<String, Number> costs = (Map<String, Number>) body.get("costs");

            LocalDate date = LocalDate.parse(dateStr);
            String periodKey = "weekly".equalsIgnoreCase(type) ? weekKey(date) : monthKey(date);

            boolean replaceAll = Boolean.TRUE.equals(body.get("replaceAll"));

            String key = "users/%s/costs/%s/%s.json".formatted(username, type.toLowerCase(), periodKey);
            Map<String, Object> period = loadJsonOrEmpty(key);

            // init fields if new
            period.putIfAbsent("periodKey", periodKey);
            period.putIfAbsent("days", new LinkedHashMap<String, Object>());
            period.putIfAbsent("totals", new LinkedHashMap<String, Object>());

            @SuppressWarnings("unchecked")
            Map<String, Object> days = (Map<String, Object>) period.get("days");
            @SuppressWarnings("unchecked")
            Map<String, Object> totals = (Map<String, Object>) period.get("totals");

            // If replaceAll, clear all existing day entries so the new values become the totals
            if (replaceAll) {
                days.clear();
            }

            String dayKey = date.toString();
            @SuppressWarnings("unchecked")
            Map<String, Object> dayCosts = (Map<String, Object>) days.getOrDefault(dayKey, new LinkedHashMap<>());

            // Set day values (simple overwrite, no delta tracking)
            for (var e : costs.entrySet()) {
                String cat = e.getKey();
                double incoming = e.getValue() == null ? 0.0 : round2(e.getValue().doubleValue());
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
                // compute Sunday-start week
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
            return ResponseEntity.ok(period);

        } catch (Exception ex) {
            ex.printStackTrace();
            return ResponseEntity.status(500).body("merge-dated failed: " + ex.getMessage());
        }
    }

    private Map<String, Object> loadJsonOrEmpty(String key) throws Exception {
        try {
            byte[] raw = s3Service.downloadFile(key);
            return new ObjectMapper().readValue(raw, new TypeReference<Map<String,Object>>() {});
        } catch (Exception e) {
            return new LinkedHashMap<>();
        }
    }

    private void saveJson(String key, Map<String, Object> payload) throws Exception {
        String json = new ObjectMapper().writeValueAsString(payload);
        try (var in = new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8))) {
            s3Service.uploadFile(key, in, json.length());
        }
    }

    private static double round2(double v) {
        return Math.round(v * 100.0) / 100.0;
    }

    // Feedback
    static record CatDelta(
        String category,
        double current,
        double previous,
        double delta,      // current - previous
        Double pct         // null if previous==0
    ) {}

    static record MonthlyFeedback(
        String month,              // "YYYY-MM"
        String previousMonth,      // most recent compared month "YYYY-MM"
        double totalCurrent,
        double totalPrevious,      // average across up to 6 prior months
        double totalDelta,         // current - average
        java.util.List<CatDelta> deltas,
        boolean overBudget,
        Double monthlyBudget,
        java.util.List<CatDelta> cutbacks,
        int monthsCompared         // how many prior months were averaged
    ) {}

    /** Helper: parse "YYYY-MM" and return previous month as "YYYY-MM" */
    private static String prevMonthKey(String month) {
        YearMonth ym = YearMonth.parse(month);
        YearMonth pm = ym.minusMonths(1);
        return String.format("%04d-%02d", pm.getYear(), pm.getMonthValue());
    }

    /** Helper: sum the "totals" map from a monthly period file (if missing, returns empty map). */
    @SuppressWarnings("unchecked")
    private Map<String, Double> readMonthlyTotalsOrEmpty(String username, String monthKey) throws Exception {
        String s3Key = "users/%s/costs/monthly/%s.json".formatted(normalize(username), monthKey);
        Map<String,Object> period = loadJsonOrEmpty(s3Key);
        Object totalsObj = period.get("totals");
        if (totalsObj instanceof Map<?,?> raw) {
            Map<String, Double> out = new LinkedHashMap<>();
            for (var e : raw.entrySet()) {
                String k = String.valueOf(e.getKey());
                Object v = e.getValue();
                if (v instanceof Number n) out.put(k, round2(n.doubleValue()));
            }
            return out;
        }
        return new LinkedHashMap<>();
    }

    /** GET /api/costs/feedback/{username}?month=YYYY-MM  */
    @GetMapping("/feedback/{username}")
    public ResponseEntity<?> getMonthlyFeedback(
            @PathVariable String username,
            @RequestParam(name = "month") String month // "YYYY-MM"
    ) {
        try {
            String normUser = normalize(username);

            // Load fixed costs once
            List<Map<String, Object>> fixedCosts = loadFixedCosts(normUser);

            // Load and enrich current month
            Map<String, Double> curTotals = readMonthlyTotalsOrEmpty(normUser, month);
            for (var fc : fixedCosts) {
                String cat = String.valueOf(fc.get("category"));
                double amt = fc.get("amount") instanceof Number ? ((Number) fc.get("amount")).doubleValue() : 0.0;
                if (amt > 0) curTotals.merge(cat, amt, Double::sum);
            }

            // Collect up to 6 prior months — only those where the user tracked variable data
            YearMonth ym = YearMonth.parse(month);
            java.util.List<Map<String, Double>> priorMonths = new java.util.ArrayList<>();
            String mostRecentPrevKey = null;

            for (int i = 1; i <= 6; i++) {
                YearMonth prevYM = ym.minusMonths(i);
                String prevKey = String.format("%04d-%02d", prevYM.getYear(), prevYM.getMonthValue());
                Map<String, Double> rawPrev = readMonthlyTotalsOrEmpty(normUser, prevKey);
                if (rawPrev.isEmpty()) continue; // no tracked data for this month

                // Enrich with fixed costs for fair comparison
                Map<String, Double> enriched = new LinkedHashMap<>(rawPrev);
                for (var fc : fixedCosts) {
                    String cat = String.valueOf(fc.get("category"));
                    double amt = fc.get("amount") instanceof Number ? ((Number) fc.get("amount")).doubleValue() : 0.0;
                    if (amt > 0) enriched.merge(cat, amt, Double::sum);
                }

                if (mostRecentPrevKey == null) mostRecentPrevKey = prevKey;
                priorMonths.add(enriched);
            }

            int monthsCompared = priorMonths.size();

            // Build per-category averages across all N prior months (missing months count as $0)
            Map<String, Double> avgPrevTotals = new LinkedHashMap<>();
            if (monthsCompared > 0) {
                java.util.Set<String> allPrevCats = new java.util.LinkedHashSet<>();
                for (var m : priorMonths) allPrevCats.addAll(m.keySet());
                for (String cat : allPrevCats) {
                    double sum = 0.0;
                    for (var m : priorMonths) sum += m.getOrDefault(cat, 0.0);
                    avgPrevTotals.put(cat, round2(sum / monthsCompared));
                }
            }

            // Union of categories
            java.util.Set<String> cats = new java.util.TreeSet<>();
            cats.addAll(curTotals.keySet());
            cats.addAll(avgPrevTotals.keySet());

            java.util.List<CatDelta> deltas = new java.util.ArrayList<>();
            double totalCur = 0.0, totalPrev = 0.0;

            for (String c : cats) {
                double cur = round2(curTotals.getOrDefault(c, 0.0));
                double pre = round2(avgPrevTotals.getOrDefault(c, 0.0));
                double d   = round2(cur - pre);
                Double pct = (pre == 0.0) ? null : round2(d / pre);
                deltas.add(new CatDelta(c, cur, pre, d, pct));
                totalCur  += cur;
                totalPrev += pre;
            }
            totalCur  = round2(totalCur);
            totalPrev = round2(totalPrev);

            double monthlyBudget = totalPrev; // fallback: avg spend as soft budget
            boolean overBudget = totalCur > monthlyBudget && monthlyBudget > 0;

            double overAmount = overBudget ? round2(totalCur - monthlyBudget) : 0.0;
            java.util.List<CatDelta> cutbacks = new java.util.ArrayList<>();
            if (overBudget && overAmount > 0) {
                java.util.List<CatDelta> overs = deltas.stream()
                        .filter(d -> d.delta > 0)
                        .sorted((a, b) -> Double.compare(b.delta, a.delta))
                        .toList();
                double remaining = overAmount;
                for (CatDelta d : overs) {
                    double take = Math.min(d.delta, remaining);
                    cutbacks.add(new CatDelta(d.category, d.current, d.previous, round2(take), d.pct));
                    remaining = round2(remaining - take);
                    if (remaining <= 0) break;
                }
            }

            String prevLabel = mostRecentPrevKey != null ? mostRecentPrevKey : prevMonthKey(month);
            MonthlyFeedback payload = new MonthlyFeedback(
                month,
                prevLabel,
                totalCur,
                totalPrev,
                round2(totalCur - totalPrev),
                deltas,
                overBudget,
                monthlyBudget > 0 ? monthlyBudget : null,
                cutbacks,
                monthsCompared
            );

            // Trophy hooks
            try {
                if (!overBudget && monthlyBudget > 0) {
                    userProfileService.incrementTrophy(username, "monthly-budget-met", 1);
                    if (totalCur <= monthlyBudget * 0.95) {
                        userProfileService.incrementTrophy(username, "budget-pacer", 1);
                    }
                }
                CatDelta eatOut = deltas.stream().filter(d -> d.category.toLowerCase().contains("eat")).findFirst().orElse(null);
                CatDelta groceries = deltas.stream().filter(d -> d.category.toLowerCase().contains("groc")).findFirst().orElse(null);
                if (eatOut != null && eatOut.delta < 0 && (groceries == null || groceries.delta >= 0)) {
                    userProfileService.incrementTrophy(username, "healthy-eater", 1);
                }
            } catch (Exception ignore) { /* non-fatal */ }

            return ResponseEntity.ok(payload);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Set desired monthly totals. Adjustments are stored separately from day entries
     * so monthly-only costs (like rent) don't appear in weekly charts.
     */
    @PostMapping("/monthly/{username}/set-totals")
    public ResponseEntity<?> setMonthlyTotals(
            @PathVariable String username,
            @RequestParam String month,
            @RequestBody Map<String, Object> body) {
        try {
            String normUser = normalize(username);
            @SuppressWarnings("unchecked")
            Map<String, Number> costsRaw = (Map<String, Number>) body.get("costs");
            Map<String, Double> costs = new LinkedHashMap<>();
            if (costsRaw != null) {
                for (var e : costsRaw.entrySet()) {
                    costs.put(e.getKey(), e.getValue() == null ? 0.0 : e.getValue().doubleValue());
                }
            }

            // Exclude fixed cost categories so setMonthlyTotals doesn't zero them out
            // (fixed costs are merged into totals separately on GET)
            List<Map<String, Object>> fixedCosts = loadFixedCosts(normUser);
            Set<String> fixedCatNames = new HashSet<>();
            for (var fc : fixedCosts) {
                fixedCatNames.add(String.valueOf(fc.get("category")).toLowerCase());
            }
            costs.keySet().removeIf(k -> fixedCatNames.contains(k.toLowerCase()));

            Map<String, Object> result = costsService.setMonthlyTotals(normUser, month, costs);
            if (result == null) {
                return ResponseEntity.status(500).body("Failed to set monthly totals");
            }
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.status(500).body("set-monthly-totals failed: " + e.getMessage());
        }
    }

    // ==================== Transaction Management ====================

    /** GET /api/costs/transactions/{username}?month=YYYY-MM */
    @GetMapping("/transactions/{username}")
    public ResponseEntity<?> getTransactions(
            @PathVariable String username,
            @RequestParam(name = "month") String month) {
        try {
            String normUser = normalize(username);
            List<Map<String, Object>> txns = costsService.getTransactions(normUser, month);
            return ResponseEntity.ok(txns);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    /** PUT /api/costs/transactions/{username}/{txnId}?month=YYYY-MM */
    @PutMapping("/transactions/{username}/{txnId}")
    public ResponseEntity<?> editTransaction(
            @PathVariable String username,
            @PathVariable String txnId,
            @RequestParam(name = "month") String month,
            @RequestBody Map<String, Object> body) {
        try {
            String normUser = normalize(username);
            double newAmount = 0.0;
            Object amountObj = body.get("amount");
            if (amountObj instanceof Number) newAmount = ((Number) amountObj).doubleValue();

            Map<String, Object> result = costsService.editTransaction(normUser, month, txnId, newAmount);
            if (result == null) {
                return ResponseEntity.status(404).body(Map.of("error", "Transaction not found"));
            }
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    /** PUT /api/costs/transactions/{username}/{txnId}/category?month=YYYY-MM */
    @PutMapping("/transactions/{username}/{txnId}/category")
    public ResponseEntity<?> recategorizeTransaction(
            @PathVariable String username,
            @PathVariable String txnId,
            @RequestParam(name = "month") String month,
            @RequestBody Map<String, Object> body) {
        try {
            String normUser = normalize(username);
            String newCategory = (String) body.get("category");
            if (newCategory == null || newCategory.isBlank()) {
                return ResponseEntity.badRequest().body(Map.of("error", "category is required"));
            }
            Map<String, Object> result = costsService.recategorizeTransaction(normUser, month, txnId, newCategory);
            if (result == null) {
                return ResponseEntity.status(404).body(Map.of("error", "Transaction not found"));
            }
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    /** POST /api/costs/transactions/{username}/{txnId}/revert?month=YYYY-MM */
    @PostMapping("/transactions/{username}/{txnId}/revert")
    public ResponseEntity<?> revertTransaction(
            @PathVariable String username,
            @PathVariable String txnId,
            @RequestParam(name = "month") String month) {
        try {
            String normUser = normalize(username);
            Map<String, Object> result = costsService.revertTransaction(normUser, month, txnId);
            if (result == null) {
                return ResponseEntity.status(404).body(Map.of("error", "Transaction not found"));
            }
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    /** DELETE /api/costs/transactions/{username}/{txnId}?month=YYYY-MM */
    @DeleteMapping("/transactions/{username}/{txnId}")
    public ResponseEntity<?> deleteTransaction(
            @PathVariable String username,
            @PathVariable String txnId,
            @RequestParam(name = "month") String month) {
        try {
            String normUser = normalize(username);
            boolean deleted = costsService.deleteTransaction(normUser, month, txnId);
            if (!deleted) {
                return ResponseEntity.status(404).body(Map.of("error", "Transaction not found"));
            }
            return ResponseEntity.ok(Map.of("success", true));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    // ==================== Fixed Monthly Costs ====================

    /** GET /api/costs/fixed/{username} — list all fixed monthly costs */
    @GetMapping("/fixed/{username}")
    public ResponseEntity<?> getFixedCosts(@PathVariable String username) {
        try {
            String normUser = normalize(username);
            List<Map<String, Object>> fixed = loadFixedCosts(normUser);
            return ResponseEntity.ok(fixed);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    /** POST /api/costs/fixed/{username} — add or update a fixed cost */
    @PostMapping("/fixed/{username}")
    public ResponseEntity<?> saveFixedCost(
            @PathVariable String username,
            @RequestBody Map<String, Object> body) {
        try {
            String normUser = normalize(username);
            List<Map<String, Object>> fixed = loadFixedCosts(normUser);

            String id = body.get("id") != null ? String.valueOf(body.get("id")) : null;
            String category = (String) body.get("category");
            double amount = body.get("amount") instanceof Number
                    ? ((Number) body.get("amount")).doubleValue() : 0.0;

            if (category == null || category.isBlank()) {
                return ResponseEntity.badRequest().body(Map.of("error", "category is required"));
            }

            if (id != null && !id.isBlank()) {
                // Update existing by id
                for (var fc : fixed) {
                    if (id.equals(fc.get("id"))) {
                        fc.put("category", category);
                        fc.put("amount", round2(amount));
                        break;
                    }
                }
            } else {
                // Check if a fixed cost with the same category already exists — overwrite it
                boolean found = false;
                for (var fc : fixed) {
                    if (category.equalsIgnoreCase(String.valueOf(fc.get("category")))) {
                        fc.put("amount", round2(amount));
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    Map<String, Object> entry = new LinkedHashMap<>();
                    entry.put("id", java.util.UUID.randomUUID().toString());
                    entry.put("category", category);
                    entry.put("amount", round2(amount));
                    fixed.add(entry);
                }
            }

            saveFixedCosts(normUser, fixed);
            return ResponseEntity.ok(fixed);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    /** DELETE /api/costs/fixed/{username}/{id} — remove a fixed cost */
    @DeleteMapping("/fixed/{username}/{id}")
    public ResponseEntity<?> deleteFixedCost(
            @PathVariable String username,
            @PathVariable String id) {
        try {
            String normUser = normalize(username);
            List<Map<String, Object>> fixed = loadFixedCosts(normUser);
            boolean removed = fixed.removeIf(fc -> id.equals(fc.get("id")));
            if (!removed) {
                return ResponseEntity.status(404).body(Map.of("error", "Fixed cost not found"));
            }
            saveFixedCosts(normUser, fixed);
            return ResponseEntity.ok(fixed);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    private List<Map<String, Object>> loadFixedCosts(String username) {
        try {
            String key = "users/" + username + "/fixed_costs.json";
            byte[] data = s3Service.downloadFile(key);
            if (data == null || data.length == 0) return new ArrayList<>();
            return new ObjectMapper().readValue(data, new TypeReference<List<Map<String, Object>>>() {});
        } catch (Exception e) {
            return new ArrayList<>();
        }
    }

    private void saveFixedCosts(String username, List<Map<String, Object>> fixed) throws Exception {
        String key = "users/" + username + "/fixed_costs.json";
        String json = new ObjectMapper().writeValueAsString(fixed);
        s3Service.uploadFile(key,
                new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8)),
                json.length());
    }
}
