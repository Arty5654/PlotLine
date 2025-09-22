package com.plotline.backend.controller;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.WeeklyMonthlyCostRequest;
import com.plotline.backend.service.S3Service;
import com.plotline.backend.service.OCRService;
import com.plotline.backend.service.OpenAIService;

import io.jsonwebtoken.io.IOException;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

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

    @PostMapping
    public ResponseEntity<String> saveWeeklyMonthlyCosts(@RequestBody WeeklyMonthlyCostRequest request) {
        try {
            // Ensure all costs are stored as Double
            //request.getCosts().replaceAll((k, v) -> Double.valueOf(String.valueOf(v)));
 
            // Convert request object to JSON string
            String jsonData = new ObjectMapper().writeValueAsString(request);

            // Convert string to InputStream for S3 upload
            ByteArrayInputStream inputStream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));

            // Generate a unique S3 key per user
            String key = "users/" + request.getUsername() + "/" + request.getType() + "_costs.json";

            // Upload the file to S3 using S3Service
            //s3Service.uploadFile(key, inputStream, jsonData.length());
            //updateWeeklyCosts(request.getUsername(), request.getCosts());
            overwriteCosts(request.getUsername(), request.getType(), request.getCosts());

            return ResponseEntity.ok("Weekly/Monthly costs saved successfully.");
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error saving data: " + e.getMessage());
        }
    }

    @GetMapping("/{username}/{type}")
    public ResponseEntity<String> getWeeklyMonthlyCosts(@PathVariable String username, @PathVariable String type) {
        try {
            // Determine current week or month
            //int period = determinePeriod(type);

            // Generate the key dynamically
            String key = "users/" + username + "/" + type + "_costs" + ".json";

            // Fetch data from S3
            byte[] fileData = s3Service.downloadFile(key);
            String jsonData = new String(fileData, StandardCharsets.UTF_8);

            return ResponseEntity.ok(jsonData);
        } catch (Exception e) {
           // Instead of returning `{}`, return a valid empty response that matches the expected format
            String emptyJson = "{ \"username\": \"" + username + "\", \"type\": \"" + type + "\", \"costs\": {} }";
            return ResponseEntity.ok(emptyJson);
        }
    }


    @DeleteMapping("/{username}/{type}")
    public ResponseEntity<String> deleteWeeklyMonthlyCosts(@PathVariable String username, @PathVariable String type) {
        try {
            // Generate key to delete
            String key = "users/" + username + "/" + type + "_costs.json";

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

            updateWeeklyCosts(username, parsed);

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
        Map<String, Object> data = Map.of(
            "username", username,
            "type",     type,
            "costs",    newCosts
        );

        String key = "users/" + username + "/" + type + "_costs.json";
        String json = new ObjectMapper().writeValueAsString(data);
        s3Service.uploadFile(key,
            new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8)),
            json.length());
    }


    private void mergeCosts(String username,
        String type,
        Map<String, Double> delta) throws Exception {

        String key = "users/" + username + "/" + type + "_costs.json";

        // 1.  Load existing file (or create an empty shell)
        Map<String,Object> data;
        try {
        byte[] raw = s3Service.downloadFile(key);
        data = new ObjectMapper().readValue(raw, new TypeReference<>() {});
        } catch (Exception e) {           // file doesn’t exist yet
        data = new HashMap<>();
        data.put("username", username);
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
        try { mergeCosts(username, "weekly", delta); }
        catch (Exception e){                       // you can log if you like
        System.err.println("merge error: "+e.getMessage());
        }
    }

    @PostMapping("/merge")
        public ResponseEntity<String> merge(@RequestBody WeeklyMonthlyCostRequest req){
        try {
        mergeCosts(req.getUsername(), req.getType(), req.getCosts());
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

    @PostMapping("/merge-dated")
    public ResponseEntity<?> mergeDatedCosts(@RequestBody Map<String, Object> body) {
        try {
            String username = String.valueOf(body.get("username"));
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
                double add = e.getValue() == null ? 0.0 : e.getValue().doubleValue();
                if (add == 0.0) continue;
                dayCosts.put(cat, round2(dayCosts.getOrDefault(cat, 0.0) + add));
                totals.put(cat, round2(totals.getOrDefault(cat, 0.0) + add));
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

}
