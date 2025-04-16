package com.plotline.backend.controller;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.BudgetQuizRequest;
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
    public ResponseEntity<?> generateBudget(@RequestBody BudgetQuizRequest request) {
        try {
            // Prompt LLM
            String prompt = String.format("""
                Generate a JSON object for a monthly budget for someone living in %s,
                earning $%.2f yearly, supporting %d dependents, with a %s spending style.
                Categories must include rent, groceries, subscriptions, savings, investments,
                and can optionally include entertainment, eating out, utilities, or other.
                Response format: {"Rent": 1200, "Groceries": 400, ...}
            """, request.getLocation(), request.getYearlyIncome(), request.getDependents(), request.getSpendingStyle());

            String json = openAIService.generateBudget(prompt);

            // Convert to Map
            Map<String, Double> monthlyBudget = objectMapper.readValue(json, new TypeReference<>() {});
            Map<String, Double> weeklyBudget = new HashMap<>();
            for (var entry : monthlyBudget.entrySet()) {
                weeklyBudget.put(entry.getKey(), entry.getValue() / 4.0); // Divide by 4
            }

            // Save both monthly and weekly budgets (original + editable copies)
            saveToS3(request.getUsername(), "monthly-budget.json", monthlyBudget);
            saveToS3(request.getUsername(), "monthly-budget-edited.json", monthlyBudget);
            saveToS3(request.getUsername(), "weekly-budget.json", weeklyBudget);
            saveToS3(request.getUsername(), "weekly-budget-edited.json", weeklyBudget);

            return ResponseEntity.ok(monthlyBudget); // You can also return the whole payload
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body("Error generating budget: " + e.getMessage());
        }
    }

    private void saveToS3(String username, String fileName, Map<String, Double> budget) throws Exception {
        String key = "users/" + username + "/" + fileName;
        String jsonData = objectMapper.writeValueAsString(budget);
        ByteArrayInputStream stream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));
        s3Service.uploadFile(key, stream, jsonData.length());
    }
}
