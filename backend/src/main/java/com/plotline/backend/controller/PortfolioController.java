package com.plotline.backend.controller;
import com.plotline.backend.service.OpenAIService;
import com.plotline.backend.service.PortfolioService;
import com.plotline.backend.dto.SavedPortfolio;
import com.plotline.backend.dto.SavedPortfolio.AccountType;
import com.plotline.backend.service.S3Service;
import com.plotline.backend.service.UserProfileService;

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

    @Autowired
    private UserProfileService userProfileService;

    @PostMapping("/portfolio")
    public ResponseEntity<String> generatePortfolio(@RequestBody Map<String, String> quizData) {
        try {
            String username = quizData.get("username");
            AccountType accountType = AccountType.fromString(quizData.get("account"));

            // Delete original portfilio if user takes the quiz again
            portfolioService.deleteOriginalPortfolio(username, accountType);

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
                JsonNode investmentsNode = budgetJson.get("budget").get("Brokerage");
                if (accountType == AccountType.ROTH_IRA && budgetJson.has("Roth IRA")) {
                    investmentAmount = budgetJson.get("Roth IRA").asText();
                } else if (budgetJson.has("Brokerage")) {
                    investmentAmount = budgetJson.get("Brokerage").asText();
                }
            } catch (Exception e) {
                System.out.println("No budget file or investment key found, using income fallback.");
            }

            String amountBasis = (investmentAmount != null && !investmentAmount.isEmpty()) ? 
                "$" + investmentAmount + "/month (based on budget)" : 
                "$" + income + " annual income";
            
            // Different prompt for Roth IRA
            String accountHint = (accountType == AccountType.ROTH_IRA)
                ? """
                    You are constructing a portfolio **for a Roth IRA** (tax-free qualified withdrawals, contributions limited annually).
                    Keep the format identical; you may emphasize long-term growth and tax-inefficient assets are fine here.
                    """
                : """
                    You are constructing a portfolio **for a taxable brokerage account**.
                    Prefer tax efficiency (e.g., broad index ETFs; avoid unnecessary turnover).
                    """;

            // Create prompt
            String prompt = String.format("""
            Based on the following quiz:
            - Goal: %s
            - Risk Tolerance: %s
            - Experience: %s
            - Age: %s
            - Suggested Monthly Investment: %s

            %s

            Recommend a diversified investment portfolio. 

            IMPORTANT FORMAT REQUIREMENT:  
            Follow **this exact format** for each asset so the app can parse it:

            **[TICKER] - [PERCENTAGE]%%%%**  
            - **Allocation:** $XXX.XX  
            - **Reason:** Explanation of why this asset was chosen.

            For example:
            **VTI - 40%%%%**  
            - **Allocation:** $264.80  
            - **Reason:** Broad U.S. stock market exposure.

            Use 4-5 ETFs or stocks max. Do not include full fund names or vary the bullet format. Make it beginner-friendly.
            """,
            quizData.get("goals"),
            quizData.get("riskTolerance"),
            quizData.get("experience"),
            quizData.get("age"),
            amountBasis,
            accountHint
            );


            String response = openAIService.generateResponsePortfolio(prompt);

            // Automatically save original portfolio
            // SavedPortfolio original = new SavedPortfolio();
            // original.setUsername(username);
            // original.setPortfolio(response);
            // original.setRiskTolerance(quizData.get("riskTolerance"));
            // portfolioService.saveOriginalPortfolio(username, original);
            
            // Clean up old edited portfolio
            portfolioService.deleteEditedPortfolio(username);

            // save trophy progress for making portfolio
            userProfileService.incrementTrophy(username, "llm-investor", 1);

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error generating portfolio");
        }
    }

    @PostMapping("/portfolio/save-original")
    public ResponseEntity<String> saveOriginalPortfolio(@RequestBody SavedPortfolio portfolio) {
        try {
            if (portfolio.getAccount() == null) {
                portfolio.setAccount(SavedPortfolio.AccountType.BROKERAGE);
            }
            portfolioService.saveOriginalPortfolio(portfolio.getUsername(), portfolio.getAccount(), portfolio);
            return ResponseEntity.ok("Original portfolio saved");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("Failed to save original portfolio: " + e.getMessage());
        }
    }



    @PostMapping("/portfolio/save")
    public ResponseEntity<String> saveEditedPortfolio(@RequestBody SavedPortfolio newPortfolio) {
        try {
            if (newPortfolio.getAccount() == null) {
                newPortfolio.setAccount(SavedPortfolio.AccountType.BROKERAGE);
            }
            portfolioService.saveEditedPortfolio(newPortfolio.getUsername(), newPortfolio.getAccount(), newPortfolio);
            return ResponseEntity.ok("Edited portfolio saved.");
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Failed to save edited portfolio.");
        }
    }

    @GetMapping("/portfolio/{username}")
    public ResponseEntity<SavedPortfolio> getPortfolio(@PathVariable String username, @RequestParam(name="account", defaultValue="BROKERAGE") AccountType account) {
        SavedPortfolio edited = portfolioService.loadEditedPortfolio(username, account);
        System.out.println("Edited: " + edited);
        
        if (edited != null) {
            return ResponseEntity.ok(edited);
        } else {
            // Fallback to original if edited doesn't exist
            SavedPortfolio original = portfolioService.loadOriginalPortfolio(username, account);
            if (original != null) {
                //System.out.println("Here??");
                return ResponseEntity.ok(original);
            }
        }
    
        return ResponseEntity.notFound().build();
    }    

    @PostMapping("/portfolio/revert/{username}")
    public ResponseEntity<String> revertToOriginal(@PathVariable String username, @RequestParam(name = "account", defaultValue = "BROKERAGE") AccountType account) {
        SavedPortfolio original = portfolioService.loadOriginalPortfolio(username, account);
        if (original == null) {
            return ResponseEntity.status(404).body("Original portfolio not found");
        }
        portfolioService.saveEditedPortfolio(username, account, original);
        // Clean up old edited portfolio
        portfolioService.deleteEditedPortfolio(username, account);
        return ResponseEntity.ok("Reverted to original portfolio");
    }

    // For Stock News
    @GetMapping("/portfolio/risk/{username}")
    public ResponseEntity<String> getRiskTolerance(@PathVariable String username, @RequestParam(name = "account", defaultValue = "BROKERAGE") AccountType account) {
        // Try to load the edited portfolio first
        SavedPortfolio portfolio = portfolioService.loadEditedPortfolio(username, account);
    
        // If no edited portfolio or risk is invalid, try to load the original
        if (portfolio == null || portfolio.getRiskTolerance() == null || portfolio.getRiskTolerance().equalsIgnoreCase("Edited")) {
            portfolio = portfolioService.loadOriginalPortfolio(username, account);
    
            // If still null or invalid, return default
            if (portfolio == null || portfolio.getRiskTolerance() == null) {
                return ResponseEntity.ok("Medium");
            }
        }
    
        System.out.println("RISK FOR NEWS: " + portfolio.getRiskTolerance());
        return ResponseEntity.ok(portfolio.getRiskTolerance());
    }
    

}

