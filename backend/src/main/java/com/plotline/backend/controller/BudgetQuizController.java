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
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

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
            List<String> categories = (List<String>) quizData.get("categories");
            Map<String, Double> knownCosts = (Map<String, Double>) quizData.getOrDefault("knownCosts", Map.of());

            String knownAllocations = knownCosts.entrySet().stream()
                    .map(e -> String.format("- Allocate $%.2f to %s.", ((Number) e.getValue()).doubleValue(), e.getKey()))
                    .collect(Collectors.joining("\n"));


            String categoriesList = String.join(", ", categories);

            // Dont think I need this, but just in case
            // if (categories == null || categories.isEmpty()) {
            //   categories = Arrays.asList("Rent", "Groceries", "Subscriptions", "Savings", "Investments", "Entertainment", "Eating Out", "Utilities", "Other");
            // }

            String rules;
            switch (spendingStyle.toLowerCase()) {
                case "low":
                    rules = """
                        - Limit rent to 25%% of monthly income.
                        - Save and invest at least 30%% of monthly income.
                        - Groceries should stay around 10%%.
                        - Keep entertainment and eating out under 5%% each.
                        - Transportation (including gas, public transit, etc.) should be under 5%%.
                        - Insurance (health, auto, etc.) around 8-10%%.
                        - Subscriptions should not exceed 2%%.
                        - Miscellaneous should be capped at 3%%.
                        """;
                    break;
                case "medium":
                    rules = """
                        - Allocate up to 30%% of monthly income to rent.
                        - Save and invest up to 20-25%% combined.
                        - Groceries up to 12-15%%.
                        - Entertainment and eating out can be up to 10%% each.
                        - Transportation (gas, rideshare, car payments) can be up to 8%%.
                        - Insurance (health, auto, etc.) up to 10-12%%.
                        - Subscriptions should stay under 4%%.
                        - Miscellaneous spending should be under 5%%.
                        """;
                    break;
                case "high":
                    rules = """
                        - Allow up to 35%% of monthly income for rent.
                        - Save and invest 10-15%% combined.
                        - Groceries can be up to 15%%.
                        - Entertainment and eating out may go up to 15%% each.
                        - Transportation (car ownership, fuel, etc.) up to 10%%.
                        - Insurance costs may be up to 15%%.
                        - Subscriptions can be up to 5%%.
                        - Miscellaneous spending up to 8%%.
                        """;
                    break;
                default:
                    rules = "";
            }

            double monthlyIncome = yearlyIncome / 12;
            double budgetCap;

            switch (spendingStyle.toLowerCase()) {
                case "low":
                    budgetCap = monthlyIncome * 0.75;
                    break;
                case "medium":
                    budgetCap = monthlyIncome * 0.88;
                    break;
                case "high":
                    budgetCap = monthlyIncome * 0.97;
                    break;
                default:
                    budgetCap = monthlyIncome * 0.85;
            }


            
            String prompt = String.format("""
            You are a financial assistant helping generate a realistic monthly budget.

            Generate a JSON object for a monthly budget for someone living in %s, %s,
            earning $%.2f yearly, supporting %d dependents, with a %s spending style.

            Use ONLY these categories: %s.

            The user already knows these costs and has requested to fix them:
            %s

            Use the following budgeting rules as **general guidance** — they are recommendations, not strict constraints. Use your judgment to adjust based on cost of living, dependents, and the user's chosen categories.
            
            You **must allocate money to all user-provided categories**, even if they are not mentioned in the rules (e.g., hobbies like "Tennis"). Make sure each category has a reasonable allocation unless it clearly shouldn't apply.

            Budgeting Guidelines:
            %s

            Output format:
            {
                "Category1": amount,
                "Category2": amount,
                ...
            }

            Try to keep the total budget around $%.2f (%.0f%% of monthly income), but this is a recommendation — the **only hard rule is that the total must not exceed the user's monthly income** ($%.2f). Round each category to whole dollars.

            Ensure that savings and investments are separated, and combined they should follow the range based on spending style.
            """, city, state, yearlyIncome, dependents, spendingStyle, categoriesList, knownAllocations, rules, budgetCap, (budgetCap / monthlyIncome) * 100, monthlyIncome);

            

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
            //saveToS3(username, "monthly-budget-edited.json", monthly);
            saveToS3(username, "weekly-budget.json", weekly);
            //saveToS3(username, "weekly-budget-edited.json", weekly);

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
        String editedKey = String.format("users/%s/%s-budget-edited.json", username, type);
        s3Service.deleteFile(editedKey);
        return ResponseEntity.ok("Reverted to original budget.");
    } catch (Exception e) {
        return ResponseEntity.status(500).body("Failed to revert: " + e.getMessage());
    }
}


}
