package com.plotline.backend.controller;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.BudgetQuizRequest;
import com.plotline.backend.dto.BudgetRequest;
import com.plotline.backend.service.OpenAIService;
import com.plotline.backend.service.S3Service;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/llm/budget")
public class BudgetQuizController {

    @Autowired
    private OpenAIService openAIService;

    @Autowired
    private S3Service s3Service;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @PostMapping
    public ResponseEntity<?> generateBudget(@RequestBody Map<String, Object> quizData) {
        try {
            String username = (String) quizData.get("username");
            double yearlyIncome = Double.parseDouble(quizData.get("yearlyIncome").toString());
            String city = (String) quizData.get("city");
            String state = (String) quizData.get("state");
            int dependents = Integer.parseInt(quizData.get("dependents").toString());
            String spendingStyle = (String) quizData.get("spendingStyle");

            // Construct prompt
            String prompt = String.format("""
                Generate a JSON object for a monthly budget for someone living in %s, %s,
                earning $%.2f yearly, supporting %d dependents, with a %s spending style.
                Categories must include Rent, Groceries, Subscriptions, Savings, Investments,
                and optionally Entertainment, Eating Out, Utilities, Other.
                Output format: {"Rent": 1200, "Groceries": 400, ...}
            """, city, state, yearlyIncome, dependents, spendingStyle);

            // Get LLM output
            String rawResponse = openAIService.generateBudget(prompt);
            System.out.println("OpenAI response: " + rawResponse);

            // Extract clean JSON block from OpenAI response
            String jsonOnly = extractJsonBlock(rawResponse);

            // Parse response to map
            Map<String, Double> monthly = objectMapper.readValue(jsonOnly, new TypeReference<>() {});
            Map<String, Double> weekly = new HashMap<>();
            for (Map.Entry<String, Double> entry : monthly.entrySet()) {
                weekly.put(entry.getKey(), entry.getValue() / 4.0);
            }

            // Save all 4 versions to S3
            saveToS3(username, "monthly-budget.json", monthly);
            saveToS3(username, "monthly-budget-edited.json", monthly);
            saveToS3(username, "weekly-budget.json", weekly);
            saveToS3(username, "weekly-budget-edited.json", weekly);

            return ResponseEntity.ok(monthly);
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.internalServerError().body("Error generating budget: " + e.getMessage());
        }
    }


    private void saveToS3(String username, String fileName, Map<String, Double> budget) throws Exception {
        String key = "users/" + username + "/" + fileName;
        String jsonData = objectMapper.writeValueAsString(budget);
        ByteArrayInputStream stream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));
        s3Service.uploadFile(key, stream, jsonData.length());
    }

    private String extractJsonBlock(String text) {
      int start = text.indexOf('{');
      int end = text.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
          return text.substring(start, end + 1);
      }
      throw new IllegalArgumentException("No valid JSON object found in LLM response.");
  }
  

    // Load edited budget
    @GetMapping("/edited/{username}/{type}")
    public ResponseEntity<Object> getEditedBudget(@PathVariable String username, @PathVariable String type) {
        try {
            String key = String.format("users/%s/%s-budget-edited.json", username, type);
            byte[] data = s3Service.downloadFile(key);
            String json = new String(data, StandardCharsets.UTF_8);
            return ResponseEntity.ok(objectMapper.readValue(json, new TypeReference<Map<String, Double>>() {}));
        } catch (Exception e) {
            return ResponseEntity.status(404).body("No edited budget found.");
        }
  }

  // Save edited budget
  @PostMapping("/edited")
  public ResponseEntity<String> saveEditedBudget(@RequestBody BudgetRequest request) {
      try {
          String jsonData = objectMapper.writeValueAsString(request.getBudget());
          ByteArrayInputStream stream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));
          String key = String.format("users/%s/%s-budget-edited.json", request.getUsername(), request.getType());
          s3Service.uploadFile(key, stream, jsonData.length());
          return ResponseEntity.ok("Edited budget saved.");
      } catch (Exception e) {
          return ResponseEntity.status(500).body("Failed to save edited budget: " + e.getMessage());
      }
  }

  // Revert edited budget to original
  @PostMapping("/revert/{username}/{type}")
  public ResponseEntity<String> revertToOriginal(@PathVariable String username, @PathVariable String type) {
      try {
          String originalKey = String.format("users/%s/%s-budget.json", username, type);
          String editedKey = String.format("users/%s/%s-budget-edited.json", username, type);

          byte[] data = s3Service.downloadFile(originalKey);
          s3Service.uploadFile(editedKey, new ByteArrayInputStream(data), data.length);

          return ResponseEntity.ok("Reverted to original budget.");
      } catch (Exception e) {
          return ResponseEntity.status(500).body("Failed to revert: " + e.getMessage());
      }
  }

}
