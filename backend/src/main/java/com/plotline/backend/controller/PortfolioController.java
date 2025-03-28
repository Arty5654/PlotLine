package com.plotline.backend.controller;
import com.plotline.backend.service.OpenAIService;
import com.plotline.backend.service.PortfolioService;
import com.plotline.backend.dto.SavedPortfolio;
import com.plotline.backend.service.S3Service;

import org.apache.http.HttpStatus;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/llm")
public class PortfolioController {

    @Autowired
    private OpenAIService openAIService;

    @Autowired
    private PortfolioService portfolioService;

    @Autowired
    private IncomeController incomeController;

    @Autowired
    private S3Service s3Service;

    @PostMapping("/portfolio")
    public ResponseEntity<String> generatePortfolio(@RequestBody Map<String, String> quizData) {
        try {
            String username = quizData.get("username");

            // Fetch income
            ResponseEntity<String> incomeResponse = incomeController.getIncomeData(username);
            String incomeData = incomeResponse.getBody();
            ObjectMapper mapper = new ObjectMapper();
            JsonNode incomeJson = mapper.readTree(incomeData);
            String income = incomeJson.has("income") ? incomeJson.get("income").asText() : "Unknown";

            // Fetch budget for 'Investments'
            String budgetKey = "users/" + username + "/monthly-budget.json"; // or "/monthly_budget.json" if that's the convention
            String investmentAmount = null;
            try {
                byte[] budgetBytes = s3Service.downloadFile(budgetKey);
                JsonNode budgetJson = mapper.readTree(new String(budgetBytes, StandardCharsets.UTF_8));
                JsonNode investmentsNode = budgetJson.get("budget").get("Investments");
                if (investmentsNode != null) {
                    investmentAmount = investmentsNode.asText();
                }
            } catch (Exception e) {
                System.out.println("No budget file or investment key found, using income fallback.");
            }

            String amountBasis = (investmentAmount != null && !investmentAmount.isEmpty()) ? 
                "$" + investmentAmount + "/month (based on budget)" : 
                "$" + income + " annual income";

            // Create prompt
            String prompt = String.format("""
                Based on the following quiz:
                - Goal: %s
                - Risk Tolerance: %s
                - Experience: %s
                - Age: %s
                - Suggested Monthly Investment: %s

                Recommend a diversified investment portfolio with exact allocations (e.g., 40%% AAPL, 30%% VTI, 30%% BND).
                Include how often and how much the user should invest, based on their investment capacity.
                Explain briefly why each asset was chosen. Use beginner-friendly language.
                """,
                quizData.get("goals"),
                quizData.get("riskTolerance"),
                quizData.get("experience"),
                quizData.get("age"),
                amountBasis
            );

            String response = openAIService.generateResponsePortfolio(prompt);
            return ResponseEntity.ok(response);

        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error generating portfolio");
        }
    }


    @PostMapping("/portfolio/save")
    public ResponseEntity<String> savePortfolio(@RequestBody SavedPortfolio portfolio) {
        portfolioService.savePortfolio(portfolio.getUsername(), portfolio);
        return ResponseEntity.ok("Saved");
    }

    @GetMapping("/portfolio/{username}")
    public ResponseEntity<SavedPortfolio> getSavedPortfolio(@PathVariable String username) {
        SavedPortfolio portfolio = portfolioService.loadPortfolio(username);
        if (portfolio != null) {
            return ResponseEntity.ok(portfolio);
        } else {
            return ResponseEntity.notFound().build();
        }
    }

}

