package com.plotline.backend.controller;
import com.plotline.backend.service.OpenAIService;
import com.plotline.backend.service.PortfolioService;
import com.plotline.backend.dto.SavedPortfolio;

import org.apache.http.HttpStatus;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;

import java.io.IOException;  
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

    @PostMapping("/portfolio")
    public ResponseEntity<String> generatePortfolio(@RequestBody Map<String, String> quizData) {
        try {
            String username = quizData.get("username");

            ResponseEntity<String> incomeResponse = incomeController.getIncomeData(username);
            String incomeData = incomeResponse.getBody();

            ObjectMapper mapper = new ObjectMapper();
            JsonNode incomeJson = mapper.readTree(incomeData);
            String income = incomeJson.has("income") ? incomeJson.get("income").asText() : "Unknown";

            String prompt = String.format("""
                Based on the following quiz:
                - Goal: %s
                - Risk Tolerance: %s
                - Experience: %s
                - Monthly Budget: $%s
                - Age: $%s

                Recommend a diversified investment portfolio with exact allocations (e.g., 40%% AAPL, 30%% VTI, 30%% BND).
                Include how frequently the user should invest (e.g., $500/month), using their annual income as a guide.
                Explain briefly why each asset was chosen.
                Format the output clearly for a beginner.
                """,
                quizData.get("goals"),
                quizData.get("riskTolerance"),
                quizData.get("experience"),
                quizData.get("age"),
                income
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

