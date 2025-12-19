package com.plotline.backend.controller;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.WeeklyMonthlyCostRequest;
import com.plotline.backend.service.S3Service;
import com.plotline.backend.service.OCRService;
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
import java.util.HashMap;
import java.util.Map;
import java.util.stream.Collectors;

import java.util.Objects;
import java.util.LinkedHashMap;
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
            @RequestParam("username") String username) {
        try {
            String normUser = normalize(username);
            File tempFile = File.createTempFile("receipt-", ".jpg");
            image.transferTo(tempFile);

            String ocrText = OCRService.extractTextFromImage(tempFile);
            System.out.println("Extracted OCR Text:\n" + ocrText);

            String safeText = ocrText.replace("\"", "");
            String prompt = """
            You are a budgeting assistant. Based on the following receipt text, extract line items and their prices.

            Then categorize each item into one of the following budget categories:
            [Groceries, Eating Out, Transportation, Utilities, Subscriptions, Entertainment, Miscellaneous]
            If a line item doesn't clearly match a category, put it under "Unmatched".

            Return your answer as JSON like this:
            {
            "Groceries": 23.99,
            "Eating Out": 12.50,
            "Unmatched": [
                { "item": "Yoga Mat", "amount": 30.00 }
            ]
            }
            Only include a category in the JSON if the total amount for that category is greater than 0.
            Do not include categories with a value of 0.

            Receipt text:
            """ + safeText;

            String response = openAIService.generateResponse(prompt);
            System.out.println("GPT Response:\n" + response);

            // Clean up response to parse
            String cleanedJson = response
                .replaceAll("(?s)```json\\s*", "")  // remove ```json
                .replaceAll("(?s)```", "")          // remove closing ```
                .trim();

            // Parse
            Map<String, Object> result = new ObjectMapper().readValue(cleanedJson, new TypeReference<>() {});
            Map<String, Double> parsed = result.entrySet().stream()
                    .filter(e -> e.getValue() instanceof Number)
                    .map(e -> Map.entry(e.getKey(), ((Number) e.getValue()).doubleValue()))
                    .filter(e -> e.getValue() > 0) // prevent 0 values from being passed into updates
                    .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));

            updateWeeklyCosts(normUser, parsed);

            //return ResponseEntity.ok("Receipt parsed and weekly budget updated!");
            System.out.println("Result: " + result);
            return ResponseEntity.ok(result);

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

            String key = "users/%s/costs/%s/%s.json".formatted(username, type.toLowerCase(), periodKey);
            Map<String, Object> period = loadJsonOrEmpty(key);

            // init fields if new
            period.putIfAbsent("periodKey", periodKey);
            period.putIfAbsent("days", new LinkedHashMap<String, Map<String, Double>>());
            period.putIfAbsent("totals", new LinkedHashMap<String, Double>());

            @SuppressWarnings("unchecked")
            Map<String, Map<String, Double>> days = (Map<String, Map<String, Double>>) period.get("days");
            @SuppressWarnings("unchecked")
            Map<String, Double> totals = (Map<String, Double>) period.get("totals");

            String dayKey = date.toString();
            Map<String, Double> dayCosts = days.getOrDefault(dayKey, new LinkedHashMap<>());

            // merge
            for (var e : costs.entrySet()) {
                String cat = e.getKey();
                double incoming = e.getValue() == null ? 0.0 : round2(e.getValue().doubleValue());
                double prev = round2(dayCosts.getOrDefault(cat, 0.0));
                double delta = round2(incoming - prev);

                if (incoming == 0.0) {
                    // treat zero as “clear this category for the day”
                    if (prev != 0.0) {
                        dayCosts.remove(cat);
                        totals.put(cat, round2(totals.getOrDefault(cat, 0.0) - prev));
                    }
                } else {
                    dayCosts.put(cat, incoming);
                    totals.put(cat, round2(totals.getOrDefault(cat, 0.0) + delta));
                }
            }

            days.put(dayKey, dayCosts);

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
        String previousMonth,      // "YYYY-MM"
        double totalCurrent,
        double totalPrevious,
        double totalDelta,         // current - previous
        java.util.List<CatDelta> deltas,
        boolean overBudget,
        Double monthlyBudget,
        java.util.List<CatDelta> cutbacks
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
            String prev = prevMonthKey(month);

            String normUser = normalize(username);
            Map<String, Double> curTotals  = readMonthlyTotalsOrEmpty(normUser, month);
            Map<String, Double> prevTotals = readMonthlyTotalsOrEmpty(normUser, prev);

            // Union of categories
            java.util.Set<String> cats = new java.util.TreeSet<>();
            cats.addAll(curTotals.keySet());
            cats.addAll(prevTotals.keySet());

            java.util.List<CatDelta> deltas = new java.util.ArrayList<>();
            double totalCur = 0.0, totalPrev = 0.0;

            for (String c : cats) {
                double cur  = round2(curTotals.getOrDefault(c, 0.0));
                double pre  = round2(prevTotals.getOrDefault(c, 0.0));
                double d    = round2(cur - pre);
                Double pct  = (pre == 0.0) ? null : round2(d / pre);
                deltas.add(new CatDelta(c, cur, pre, d, pct));
                totalCur  += cur;
                totalPrev += pre;
            }
            totalCur  = round2(totalCur);
            totalPrev = round2(totalPrev);

            double monthlyBudget = totalPrev; // fallback: last month spend as soft budget
            boolean overBudget = totalCur > monthlyBudget && monthlyBudget > 0;

            // Build cutback suggestions: top overspenders until we cover overage
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

            MonthlyFeedback payload = new MonthlyFeedback(
                month,
                prev,
                totalCur,
                totalPrev,
                round2(totalCur - totalPrev),
                deltas,
                overBudget,
                monthlyBudget > 0 ? monthlyBudget : null,
                cutbacks
            );

            // Trophy hooks: under-budget streak + budget pacing + healthy eating shift
            try {
                if (!overBudget && monthlyBudget > 0) {
                    userProfileService.incrementTrophy(username, "monthly-budget-met", 1);
                    if (totalCur <= monthlyBudget * 0.95) {
                        userProfileService.incrementTrophy(username, "budget-pacer", 1);
                    }
                }
                // Healthy eating: eating out down and groceries up versus last month
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
}
