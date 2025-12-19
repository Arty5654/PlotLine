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

            // Save the requested type
            saveBudgetForType(username, type, budget);

            // Save the companion type (monthly <-> weekly)
            if (type.equals("monthly")) {
                Map<String, Double> weekly = scaleBudget(budget, 1.0 / 4.0);
                saveBudgetForType(username, "weekly", weekly);
            } else {
                Map<String, Double> monthly = scaleBudget(budget, 4.0);
                saveBudgetForType(username, "monthly", monthly);
            }

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
        try {
            String normUser = normalize(username);
            String normType = normalizeType(type);
            String editedKey = String.format("users/%s/%s-budget-edited.json", normUser, normType);
            byte[] data = s3Service.downloadFile(editedKey);
            String json = new String(data, StandardCharsets.UTF_8);
            Map<String, Double> budgetMap = objectMapper.readValue(json, new TypeReference<>() {});

            if (budgetMap.containsKey("Groceries")) {
                return ResponseEntity.ok(Map.of("Groceries", budgetMap.get("Groceries")));
            } else {
                return ResponseEntity.status(HttpStatus.NOT_FOUND).body("Groceries not found in budget.");
            }
        } catch (Exception e) {
            try {
                // fallback to original
                String normUser = normalize(username);
                String normType = normalizeType(type);
                String originalKey = String.format("users/%s/%s-budget.json", normUser, normType);
                byte[] data = s3Service.downloadFile(originalKey);
                Map<String, Double> budgetMap = objectMapper.readValue(data, new TypeReference<>() {});

                if (budgetMap.containsKey("Groceries")) {
                    return ResponseEntity.ok(Map.of("Groceries", budgetMap.get("Groceries")));
                } else {
                    return ResponseEntity.status(HttpStatus.NOT_FOUND).body("Groceries not found in budget.");
                }
            } catch (Exception ex) {
                // Legacy fallback with original casing
                try {
                    String normType = normalizeType(type);
                    String legacyKey = String.format("users/%s/%s-budget.json", username, normType);
                    byte[] data = s3Service.downloadFile(legacyKey);
                    Map<String, Double> budgetMap = objectMapper.readValue(data, new TypeReference<>() {});
                    if (budgetMap.containsKey("Groceries")) {
                        return ResponseEntity.ok(Map.of("Groceries", budgetMap.get("Groceries")));
                    }
                } catch (Exception ignored) { }

                return ResponseEntity.status(HttpStatus.NOT_FOUND).body("No budget found for user: " + username);
            }
        }
    }


}
