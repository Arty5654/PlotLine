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

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

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

            // Automatically save original portfolio
            // SavedPortfolio original = new SavedPortfolio();
            // original.setUsername(username);
            // original.setPortfolio(response);
            // original.setRiskTolerance(quizData.get("riskTolerance"));
            // portfolioService.saveOriginalPortfolio(username, original);            
            return ResponseEntity.ok(response);

        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error generating portfolio");
        }
    }

    @PostMapping("/portfolio/save-original")
    public ResponseEntity<String> saveOriginalPortfolio(@RequestBody SavedPortfolio portfolio) {
        try {
            portfolioService.saveOriginalPortfolio(portfolio.getUsername(), portfolio);
            return ResponseEntity.ok("Original portfolio saved");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("Failed to save original portfolio: " + e.getMessage());
        }
    }



    @PostMapping("/portfolio/save")
    public ResponseEntity<String> saveEditedPortfolio(@RequestBody SavedPortfolio newPortfolio) {
        try {
            portfolioService.saveEditedPortfolio(newPortfolio.getUsername(), newPortfolio);
            return ResponseEntity.ok("Edited portfolio saved.");
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Failed to save edited portfolio.");
        }
    }

    @GetMapping("/portfolio/{username}")
    public ResponseEntity<SavedPortfolio> getPortfolio(@PathVariable String username) {
        SavedPortfolio edited = portfolioService.loadEditedPortfolio(username);
        
        if (edited != null) {
            return ResponseEntity.ok(edited);
        } else {
            // Fallback to original if edited doesn't exist
            SavedPortfolio original = portfolioService.loadOriginalPortfolio(username);
            if (original != null) {
                return ResponseEntity.ok(original);
            }
        }
    
        return ResponseEntity.notFound().build();
    }    

    @PostMapping("/portfolio/revert/{username}")
    public ResponseEntity<String> revertToOriginal(@PathVariable String username) {
        SavedPortfolio original = portfolioService.loadOriginalPortfolio(username);
        if (original == null) {
            return ResponseEntity.status(404).body("Original portfolio not found");
        }
        portfolioService.saveEditedPortfolio(username, original);
        return ResponseEntity.ok("Reverted to original portfolio");
    }

    // For Stock News
    @GetMapping("/portfolio/risk/{username}")
    public ResponseEntity<String> getRiskTolerance(@PathVariable String username) {
        SavedPortfolio portfolio = portfolioService.loadEditedPortfolio(username);
        if (portfolio == null || portfolio.getRiskTolerance() == null || portfolio.getRiskTolerance().equalsIgnoreCase("Edited")) {
            return ResponseEntity.ok("Medium");
        }
        System.out.println("RISK FOR NEWS: " + portfolio.getRiskTolerance());
        return ResponseEntity.ok(portfolio.getRiskTolerance());
    }

}

