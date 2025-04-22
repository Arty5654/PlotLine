package com.plotline.backend.controller;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.BudgetRequest;
import com.plotline.backend.service.S3Service;
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

    // Save Budget
    @PostMapping
    public ResponseEntity<String> saveBudget(@RequestBody BudgetRequest request) {
        try {
            // Convert request to JSON string
            String jsonData = objectMapper.writeValueAsString(request);

            // Convert JSON string to InputStream
            ByteArrayInputStream inputStream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));

            // Generate S3 key
            String key = String.format(S3_BUCKET_PATH2, request.getUsername(), request.getType());

            // Upload to S3
            s3Service.uploadFile(key, inputStream, jsonData.length());

            return ResponseEntity.ok("Budget data saved successfully.");
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error saving budget: " + e.getMessage());
        }
    }

    // Get Budget
    @GetMapping("/{username}/{type}")
    public ResponseEntity<Object> getBudget(@PathVariable String username, @PathVariable String type) {
        try {
            String editedKey = String.format("users/%s/%s-budget-edited.json", username, type);
            byte[] data = s3Service.downloadFile(editedKey);
            String json = new String(data, StandardCharsets.UTF_8);
            return ResponseEntity.ok(objectMapper.readValue(json, BudgetRequest.class));
        } catch (Exception e) {
            try {
                // Fall back to original if edited version doesn't exist
                String originalKey = String.format("users/%s/%s-budget.json", username, type);
                byte[] originalData = s3Service.downloadFile(originalKey);
                Map<String, Double> originalBudget = objectMapper.readValue(originalData, new TypeReference<>() {});
                BudgetRequest wrapped = new BudgetRequest(username, type, originalBudget);
                return ResponseEntity.ok(wrapped);
            } catch (Exception ex) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND).body("No budget found for user: " + username);
            }
        }
    }


    // Delete Budget
    @DeleteMapping("/{username}/{type}")
    public ResponseEntity<String> deleteBudget(@PathVariable String username, @PathVariable String type) {
        try {
            String key = String.format(S3_BUCKET_PATH, username, type);
            s3Service.deleteFile(key);
            return ResponseEntity.ok("Budget data deleted successfully.");
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error deleting budget: " + e.getMessage());
        }
    }

    @GetMapping("/api/budget/{username}/{type}")
    public ResponseEntity<String> getUserBudget(@PathVariable String username, @PathVariable String type) {
        try {
            String key = "users/" + username + "/" + type + "_budget.json";
            byte[] fileData = s3Service.downloadFile(key);
            String jsonData = new String(fileData, StandardCharsets.UTF_8);
            return ResponseEntity.ok(jsonData);
        } catch (Exception e) {
            return ResponseEntity.ok("{}"); // Empty JSON if no budget data
        }
    }

}
