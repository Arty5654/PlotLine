package com.plotline.backend.controller;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.BudgetRequest;
import com.plotline.backend.service.S3Service;
import static com.plotline.backend.util.UsernameUtils.normalize;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.Map;

@RestController
@RequestMapping("/api/budget")
public class BudgetController {

    @Autowired
    private S3Service s3Service;

    @Autowired
    private com.plotline.backend.service.BudgetChanges budgetChanges;

    @Autowired
    private com.plotline.backend.plan.BudgetFiles budgetFiles;

    @Autowired
    private com.plotline.backend.plan.BudgetSaves budgetSaves;

    /**
     * {line, amount}: one line of the monthly budget (the weekly copy follows); 0 removes it. Used by
     * Track Subscriptions to keep the Subscriptions line in step with what's tracked.
     */
    @PostMapping("/{username}/line")
    public ResponseEntity<?> setLine(@PathVariable String username, @RequestBody Map<String, Object> body) {
        try {
            String user = normalize(username);
            String line = body.get("line") == null ? "" : String.valueOf(body.get("line")).strip();
            double amount = body.get("amount") instanceof Number n ? Math.round(n.doubleValue() * 100) / 100.0 : -1;
            if (line.isEmpty() || line.length() > 60 || amount < 0 || amount > 1_000_000) {
                return ResponseEntity.badRequest().body(Map.of("error", "Enter a line and an amount."));
            }
            Map<String, Double> budget = new java.util.LinkedHashMap<>(budgetFiles.monthly(user));
            if (budget.isEmpty()) return ResponseEntity.badRequest().body(Map.of("error", "Take the budget quiz first."));
            Map<String, Double> before = com.plotline.backend.plan.BudgetSaves.copy(budget);
            String key = budget.keySet().stream().filter(k -> k.equalsIgnoreCase(line)).findFirst().orElse(line);
            if (amount > 0) budget.put(key, amount); else budget.remove(key);
            budgetFiles.save(user, budget);
            budgetChanges.record(user);
            budgetSaves.changed(user, before, budget);
            return ResponseEntity.ok(Map.of("budget", budget));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(Map.of("error", "Couldn't update your budget."));
        }
    }

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final String S3_BUCKET_PATH = "users/%s/%s-budget.json";
    private final String S3_BUCKET_PATH2 = "users/%s/%s-budget-edited.json";

    private String normalizeType(String type) {
        return type == null ? "" : type.trim().toLowerCase();
    }

    private void saveBudgetForType(String username, String type, Map<String, Double> budget) throws Exception {
        String jsonData = objectMapper.writeValueAsString(new BudgetRequest(username, type, budget));
        ByteArrayInputStream inputStream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));
        String key = String.format(S3_BUCKET_PATH2, username, type);
        s3Service.uploadFile(key, inputStream, jsonData.length());
    }

    private Map<String, Double> scaleBudget(Map<String, Double> budget, double factor) {
        return budget.entrySet().stream()
                .collect(java.util.stream.Collectors.toMap(
                        Map.Entry::getKey,
                        e -> (e.getValue() == null ? 0.0 : e.getValue()) * factor
                ));
    }

    // Save Budget
    @PostMapping
    public ResponseEntity<String> saveBudget(@RequestBody BudgetRequest request) {
        try {
            String username = normalize(request.getUsername());
            String type = normalizeType(request.getType());
            Map<String, Double> budget = request.getBudget();
            if (budget == null) {
                return ResponseEntity.badRequest().body("Budget map cannot be null");
            }

            if (!type.equals("monthly") && !type.equals("weekly")) {
                return ResponseEntity.badRequest().body("Type must be 'monthly' or 'weekly'");
            }

            Map<String, Double> before = com.plotline.backend.plan.BudgetSaves.copy(budgetFiles.monthly(username));

            // Save the requested type
            saveBudgetForType(username, type, budget);

            // Save the companion type (monthly <-> weekly)
            Map<String, Double> monthly;
            if (type.equals("monthly")) {
                monthly = budget;
                Map<String, Double> weekly = scaleBudget(budget, 1.0 / 4.0);
                saveBudgetForType(username, "weekly", weekly);
            } else {
                monthly = scaleBudget(budget, 4.0);
                saveBudgetForType(username, "monthly", monthly);
            }
            budgetChanges.record(username); // tune suggestions wait a full month after a change
            budgetSaves.changed(username, before, monthly);   // fixed costs and the debt planner follow

            return ResponseEntity.ok("Budget data saved successfully.");
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error saving budget: " + e.getMessage());
        }
    }

    // Get Budget
    @GetMapping("/{username}/{type}")
    public ResponseEntity<Object> getBudget(@PathVariable String username, @PathVariable String type) {
        try {
            String normUser = normalize(username);
            String normType = normalizeType(type);
            String editedKey = String.format("users/%s/%s-budget-edited.json", normUser, normType);
            byte[] data = s3Service.downloadFile(editedKey);
            String json = new String(data, StandardCharsets.UTF_8);
            return ResponseEntity.ok(objectMapper.readValue(json, BudgetRequest.class));
        } catch (Exception e) {
            try {
                // Fall back to original if edited version doesn't exist (normalized path)
                String normUser = normalize(username);
                String normType = normalizeType(type);
                String originalKey = String.format("users/%s/%s-budget.json", normUser, normType);
                byte[] originalData = s3Service.downloadFile(originalKey);
                Map<String, Double> originalBudget = objectMapper.readValue(originalData, new TypeReference<>() {});
                BudgetRequest wrapped = new BudgetRequest(normUser, normType, originalBudget);
                return ResponseEntity.ok(wrapped);
            } catch (Exception ex) {
                // Legacy fallback: try the exact username casing that may already exist in S3
                try {
                    String rawUser = username;
                    String normType = normalizeType(type);
                    String legacyEditedKey = String.format("users/%s/%s-budget-edited.json", rawUser, normType);
                    byte[] legacyEdited = s3Service.downloadFile(legacyEditedKey);
                    String json = new String(legacyEdited, StandardCharsets.UTF_8);
                    return ResponseEntity.ok(objectMapper.readValue(json, BudgetRequest.class));
                } catch (Exception ignored) { /* fall through */ }

                try {
                    String rawUser = username;
                    String normType = normalizeType(type);
                    String legacyOriginalKey = String.format("users/%s/%s-budget.json", rawUser, normType);
                    byte[] legacyOriginal = s3Service.downloadFile(legacyOriginalKey);
                    Map<String, Double> legacyBudget = objectMapper.readValue(legacyOriginal, new TypeReference<>() {});
                    BudgetRequest wrapped = new BudgetRequest(rawUser, normType, legacyBudget);
                    return ResponseEntity.ok(wrapped);
                } catch (Exception ignored) { /* final fall-through */ }

                return ResponseEntity.status(HttpStatus.NOT_FOUND).body("No budget found for user: " + username);
            }
        }
    }


    // Delete Budget
    @DeleteMapping("/{username}/{type}")
    public ResponseEntity<String> deleteBudget(@PathVariable String username, @PathVariable String type) {
        try {
            String normUser = normalize(username);
            String normType = normalizeType(type);
            String key = String.format(S3_BUCKET_PATH, normUser, normType);
            s3Service.deleteFile(key);
            return ResponseEntity.ok("Budget data deleted successfully.");
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error deleting budget: " + e.getMessage());
        }
    }

    @GetMapping("/api/budget/{username}/{type}")
    public ResponseEntity<String> getUserBudget(@PathVariable String username, @PathVariable String type) {
        try {
            String normUser = normalize(username);
            String normType = normalizeType(type);
            String key = "users/" + normUser + "/" + normType + "_budget.json";
            byte[] fileData = s3Service.downloadFile(key);
            String jsonData = new String(fileData, StandardCharsets.UTF_8);
            return ResponseEntity.ok(jsonData);
        } catch (Exception e) {
            return ResponseEntity.ok("{}"); // Empty JSON if no budget data
        }
    }

    @GetMapping("/{username}/{type}/groceries")
    public ResponseEntity<Object> getGroceriesBudget(@PathVariable String username, @PathVariable String type) {
        String normUser = normalize(username);
        String normType = normalizeType(type);

        // Try edited file first (BudgetRequest format: {username, type, budget:{...}})
        for (String key : new String[]{
                String.format("users/%s/%s-budget-edited.json", normUser, normType),
                String.format("users/%s/%s-budget-edited.json", username, normType)
        }) {
            try {
                byte[] data = s3Service.downloadFile(key);
                BudgetRequest req = objectMapper.readValue(data, BudgetRequest.class);
                Map<String, Double> budgetMap = req.getBudget();
                if (budgetMap != null && budgetMap.containsKey("Groceries")) {
                    return ResponseEntity.ok(Map.of("Groceries", budgetMap.get("Groceries")));
                }
            } catch (Exception ignored) {}
        }

        // Fallback: original file (flat map format: {"Groceries": 100.0, ...})
        for (String key : new String[]{
                String.format("users/%s/%s-budget.json", normUser, normType),
                String.format("users/%s/%s-budget.json", username, normType)
        }) {
            try {
                byte[] data = s3Service.downloadFile(key);
                Map<String, Double> budgetMap = objectMapper.readValue(data, new TypeReference<>() {});
                if (budgetMap.containsKey("Groceries")) {
                    return ResponseEntity.ok(Map.of("Groceries", budgetMap.get("Groceries")));
                }
            } catch (Exception ignored) {}
        }

        return ResponseEntity.status(HttpStatus.NOT_FOUND).body("No budget found for user: " + username);
    }


}
