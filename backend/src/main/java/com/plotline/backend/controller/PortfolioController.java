package com.plotline.backend.controller;
import com.plotline.backend.service.OpenAIService;
import com.plotline.backend.service.PortfolioService;
import com.plotline.backend.dto.SavedPortfolio;
import com.plotline.backend.dto.SavedPortfolio.AccountType;
import com.plotline.backend.service.S3Service;
import com.plotline.backend.service.UserProfileService;
import static com.plotline.backend.util.UsernameUtils.normalize;

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
import java.util.Objects;
import java.util.LinkedHashMap;
import java.util.Iterator;

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
            String username = normalize(quizData.get("username"));
            AccountType accountType = AccountType.fromString(quizData.get("account"));

            // Delete original portfilio if user takes the quiz again
            portfolioService.deleteOriginalPortfolio(username, accountType);

            // Prefer edited monthly budget if it exists; otherwise original.
            // And support both file shapes (wrapped vs flat).
            String editedKey  = "users/" + username + "/monthly-budget-edited.json";
            String origKey    = "users/" + username + "/monthly-budget.json";

            Double brokerageEdited = null, rothEdited = null;
            Double brokerageOrig   = null, rothOrig   = null;

            try {
                byte[] b = s3Service.downloadFile(editedKey);
                Map<String, Double> m = parseBudgetBytes(b);
                brokerageEdited = m.get("Brokerage");
                rothEdited      = m.get("Roth IRA");
            } catch (Exception ignore) {}

            try {
                byte[] b = s3Service.downloadFile(origKey);
                Map<String, Double> m = parseBudgetBytes(b);
                brokerageOrig = m.get("Brokerage");
                rothOrig      = m.get("Roth IRA");
            } catch (Exception ignore) { 
                System.out.println("No original monthly budget found; using edited/income if available.");
            }

            Double chosenMonthly = null;
            boolean usedEdited = false;

            if (accountType == AccountType.ROTH_IRA) {
                // “Use edited if it’s different, else use original”
                if (rothEdited != null && !Objects.equals(rothEdited, rothOrig)) {
                    chosenMonthly = rothEdited; usedEdited = true;
                } else if (rothOrig != null) {
                    chosenMonthly = rothOrig;
                } else if (rothEdited != null) {
                    chosenMonthly = rothEdited; usedEdited = true; // edited exists but original missing
                }
            } else { // BROKERAGE
                if (brokerageEdited != null && !Objects.equals(brokerageEdited, brokerageOrig)) {
                    chosenMonthly = brokerageEdited; usedEdited = true;
                } else if (brokerageOrig != null) {
                    chosenMonthly = brokerageOrig;
                } else if (brokerageEdited != null) {
                    chosenMonthly = brokerageEdited; usedEdited = true;
                }
            }

            String amountBasis = "";
            if (chosenMonthly != null) {
                amountBasis = String.format("$%.2f/month (based on %s budget)",
                        chosenMonthly, usedEdited ? "edited" : "original");
            } else {
                System.out.println("No Budget For Investments");
            }

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

            
            // Different prompt for Roth IRA
            String prompt = String.format("""
            Based on the following quiz:
            - Goal: %s
            - Risk Tolerance: %s
            - Experience: %s
            - Age: %s
            - Time Horizon: %s
            - Tax vs Flexibility: %s
            - Withdrawal Flexibility: %s
            - Suggested Monthly Investment: %s

            %s

            Recommend a diversified investment portfolio tailored to the account type and answers above.

            For a Roth IRA:
            - Assume the money is for long-term retirement (unless the time horizon / withdrawal answers say otherwise).
            - It's okay to emphasize growth assets and tax-inefficient holdings, since qualified withdrawals are tax-free.
            - You can tilt more toward stocks for longer horizons and higher risk tolerance.

            For a taxable brokerage account:
            - Prioritize tax efficiency (broad index ETFs, fewer distributions, avoid unnecessary turnover).
            - If the user cares more about flexibility or has a short time horizon, keep the allocation more conservative and liquid.

            Use the tax vs flexibility answers to decide how aggressive you are about tax efficiency vs liquidity, and use withdrawal flexibility to determine how much should be in safer / less volatile assets.

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
                quizData.get("timeHorizon"),
                quizData.get("taxPriorty"),
                quizData.get("withdrawalFlexibility"),
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
            userProfileService.incrementTrophy(username, "investing-streak", 1);

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error generating portfolio");
        }
    }

    // Get budget for Brokerage or Roth IRA
    private Map<String, Double> parseBudgetBytes(byte[] bytes) throws Exception {
        JsonNode root = new ObjectMapper().readTree(bytes);
        // Edited file: { "username": "...", "type": "monthly", "budget": { ... } }
        // Original file: { "Rent": 1459.0, "Brokerage": 300.0, ... }
        JsonNode obj = (root.has("budget") && root.get("budget").isObject()) ? root.get("budget") : root;

        Map<String, Double> out = new LinkedHashMap<>();
        Iterator<Map.Entry<String, JsonNode>> it = obj.fields();
        while (it.hasNext()) {
            Map.Entry<String, JsonNode> e = it.next();
            JsonNode v = e.getValue();
            if (v.isNumber()) {
                out.put(e.getKey(), v.asDouble());
            } else if (v.isTextual()) {
                try { out.put(e.getKey(), Double.parseDouble(v.asText())); } catch (Exception ignore) {}
            }
        }
        return out;
    }


    @PostMapping("/portfolio/save-original")
    public ResponseEntity<String> saveOriginalPortfolio(@RequestBody SavedPortfolio portfolio) {
        try {
            if (portfolio.getAccount() == null) {
                portfolio.setAccount(SavedPortfolio.AccountType.BROKERAGE);
            }
            portfolioService.saveOriginalPortfolio(normalize(portfolio.getUsername()), portfolio.getAccount(), portfolio);
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
            portfolioService.saveEditedPortfolio(normalize(newPortfolio.getUsername()), newPortfolio.getAccount(), newPortfolio);
            return ResponseEntity.ok("Edited portfolio saved.");
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Failed to save edited portfolio.");
        }
    }

    @GetMapping("/portfolio/{username}")
    public ResponseEntity<SavedPortfolio> getPortfolio(@PathVariable String username, @RequestParam(name="account", defaultValue="BROKERAGE") AccountType account) {
        String normUser = normalize(username);
        SavedPortfolio edited = portfolioService.loadEditedPortfolio(normUser, account);
        System.out.println("Edited: " + edited);
        
        if (edited != null) {
            return ResponseEntity.ok(edited);
        } else {
            // Fallback to original if edited doesn't exist
            SavedPortfolio original = portfolioService.loadOriginalPortfolio(normUser, account);
            if (original != null) {
                //System.out.println("Here??");
                return ResponseEntity.ok(original);
            }
        }
    
        return ResponseEntity.notFound().build();
    }    

    @PostMapping("/portfolio/revert/{username}")
    public ResponseEntity<String> revertToOriginal(@PathVariable String username, @RequestParam(name = "account", defaultValue = "BROKERAGE") AccountType account) {
        String normUser = normalize(username);
        SavedPortfolio original = portfolioService.loadOriginalPortfolio(normUser, account);
        if (original == null) {
            return ResponseEntity.status(404).body("Original portfolio not found");
        }
        portfolioService.saveEditedPortfolio(normUser, account, original);
        // Clean up old edited portfolio
        portfolioService.deleteEditedPortfolio(normUser, account);
        return ResponseEntity.ok("Reverted to original portfolio");
    }

    // For Stock News
    @GetMapping("/portfolio/risk/{username}")
    public ResponseEntity<String> getRiskTolerance(@PathVariable String username, @RequestParam(name = "account", defaultValue = "BROKERAGE") AccountType account) {
        String normUser = normalize(username);
        // Try to load the edited portfolio first
        SavedPortfolio portfolio = portfolioService.loadEditedPortfolio(normUser, account);
    
        // If no edited portfolio or risk is invalid, try to load the original
        if (portfolio == null || portfolio.getRiskTolerance() == null || portfolio.getRiskTolerance().equalsIgnoreCase("Edited")) {
            portfolio = portfolioService.loadOriginalPortfolio(normUser, account);
    
            // If still null or invalid, return default
            if (portfolio == null || portfolio.getRiskTolerance() == null) {
                return ResponseEntity.ok("Medium");
            }
        }
    
        System.out.println("RISK FOR NEWS: " + portfolio.getRiskTolerance());
        return ResponseEntity.ok(portfolio.getRiskTolerance());
    }
    

}
