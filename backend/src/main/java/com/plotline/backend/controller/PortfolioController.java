package com.plotline.backend.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.plotline.backend.service.OpenAIService;
import com.plotline.backend.service.PortfolioService;
import com.plotline.backend.dto.SavedPortfolio;
import com.plotline.backend.dto.SavedPortfolio.AccountType;
import com.plotline.backend.service.S3Service;
import com.plotline.backend.service.UserProfileService;
import com.plotline.backend.investing.InvestingQuiz;
import com.plotline.backend.investing.InvestorFacts;
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
import java.time.LocalDate;
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
    private static final Logger log = LoggerFactory.getLogger(PortfolioController.class);


    @Autowired
    private OpenAIService openAIService;

    @Autowired
    private PortfolioService portfolioService;

    @Autowired
    private S3Service s3Service;

    @Autowired
    private UserProfileService userProfileService;

    @Autowired
    private InvestorFacts investorFacts;

    /**
     * What the quiz can fill in and show: income, the account's budget line, the emergency fund,
     * high-interest debts, the other account's holdings, the IRA limits, and last time's answers.
     */
    @GetMapping("/portfolio/quiz/{username}")
    public ResponseEntity<InvestorFacts.Facts> quizFacts(@PathVariable String username,
            @RequestParam(name = "account", defaultValue = "BROKERAGE") AccountType account) {
        return ResponseEntity.ok(investorFacts.load(normalize(username), account));
    }

    @PostMapping("/portfolio")
    public ResponseEntity<String> generatePortfolio(@RequestBody Map<String, String> quizData) {
        try {
            String username = normalize(quizData.get("username"));
            AccountType accountType = AccountType.fromString(quizData.get("account"));

            InvestorFacts.Facts facts = investorFacts.load(username, accountType);
            LocalDate today = LocalDate.now();
            List<String> notes = InvestingQuiz.notes(accountType, quizData, facts, today);
            String response = openAIService.generateResponsePortfolio(InvestingQuiz.prompt(accountType, quizData, facts, notes, today));

            // a new portfolio for this account replaces its edits (the app saves the new original next)
            portfolioService.deleteEditedPortfolio(username, accountType);
            investorFacts.saveAnswers(username, accountType, quizData);

            // save trophy progress for making portfolio
            userProfileService.incrementTrophy(username, "llm-investor", 1);
            userProfileService.incrementTrophy(username, "investing-streak", 1);

            return ResponseEntity.ok(InvestingQuiz.notesSection(notes) + response);

        } catch (Exception e) {
            log.error("generatePortfolio failed", e);
            return ResponseEntity.status(500).body("Error generating portfolio");
        }
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
            log.error("saveEditedPortfolio failed", e);
            return ResponseEntity.status(500).body("Failed to save edited portfolio.");
        }
    }

    @GetMapping("/portfolio/{username}")
    public ResponseEntity<SavedPortfolio> getPortfolio(@PathVariable String username, @RequestParam(name="account", defaultValue="BROKERAGE") AccountType account) {
        String normUser = normalize(username);
        SavedPortfolio edited = portfolioService.loadEditedPortfolio(normUser, account);
        log.debug("Edited: {}", edited);
        
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

    @PostMapping("/portfolio/rate")
    public ResponseEntity<?> ratePortfolio(@RequestBody Map<String, String> body) {
        try {
            String portfolioText = body.get("portfolio");
            String accountType = body.getOrDefault("accountType", "BROKERAGE");

            if (portfolioText == null || portfolioText.isBlank()) {
                return ResponseEntity.badRequest().body(Map.of("error", "Portfolio text is required"));
            }

            String rating = openAIService.ratePortfolio(portfolioText, accountType);
            // Parse into JsonNode so the response is always raw JSON, not a quoted string
            ObjectMapper mapper = new ObjectMapper();
            JsonNode ratingNode = mapper.readTree(rating);
            return ResponseEntity.ok(ratingNode);
        } catch (Exception e) {
            log.error("ratePortfolio failed", e);
            return ResponseEntity.status(500).body(Map.of("error", "Error rating portfolio"));
        }
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
    
        log.debug("RISK FOR NEWS: {}", portfolio.getRiskTolerance());
        return ResponseEntity.ok(portfolio.getRiskTolerance());
    }
    

}
