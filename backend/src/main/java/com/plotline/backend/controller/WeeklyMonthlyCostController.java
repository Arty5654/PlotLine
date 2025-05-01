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

    private void updateWeeklyCosts(String username, Map<String, Double> parsedCosts) {
        try {
            String type = "weekly";
            String key = "users/" + username + "/" + type + "_costs.json";
    
            // Step 1: Fetch existing weekly costs
            Map<String, Object> currentData;
            try {
                byte[] fileData = s3Service.downloadFile(key);
                String jsonData = new String(fileData, StandardCharsets.UTF_8);
                currentData = new ObjectMapper().readValue(jsonData, new TypeReference<>() {});
            } catch (Exception e) {
                currentData = new HashMap<>();
                currentData.put("username", username);
                currentData.put("type", type);
                currentData.put("costs", new HashMap<String, Double>());
            }
    
            // Step 2: Merge parsed costs into existing costs
            Map<String, Double> existingCosts = new HashMap<>((Map<String, Double>) currentData.get("costs"));
    
            for (Map.Entry<String, Double> entry : parsedCosts.entrySet()) {
                String category = entry.getKey();
                double newAmount = entry.getValue();
                existingCosts.put(category, existingCosts.getOrDefault(category, 0.0) + newAmount);
            }
    
            // Step 3: Save merged version back to S3
            currentData.put("costs", existingCosts);
            String updatedJson = new ObjectMapper().writeValueAsString(currentData);
            ByteArrayInputStream inputStream = new ByteArrayInputStream(updatedJson.getBytes(StandardCharsets.UTF_8));
            s3Service.uploadFile(key, inputStream, updatedJson.length());
    
        } catch (Exception e) {
            System.err.println("Error updating weekly costs: " + e.getMessage());
            e.printStackTrace();
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



}
