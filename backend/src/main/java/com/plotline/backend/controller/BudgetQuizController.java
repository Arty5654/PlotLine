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

import jakarta.annotation.PostConstruct;
import java.io.InputStream;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/llm/budget")
public class BudgetQuizController {

    @Autowired
    private OpenAIService openAIService;

    @Autowired
    private S3Service s3Service;

    private final ObjectMapper objectMapper = new ObjectMapper();

    // Tax Hash Map
    private static Map<String, Object> TAX_TABLE;     

    @PostConstruct
    void loadTaxTable() throws Exception {
        if (TAX_TABLE != null) return;                
        try (InputStream in = getClass()
                .getClassLoader()
                .getResourceAsStream("us_state_federal_tax_brackets_2024.json"))   {
            TAX_TABLE = objectMapper.readValue(in,
                    new TypeReference<>() {});
        }
    }

    // Fica Data - 2024
    private static final double SS_RATE = 0.062;             
    private static final double SS_WAGE_BASE_2024 = 168_600.0;       
    private static final double MEDICARE_RATE = 0.0145;              
    private static final double ADDL_MEDICARE_RATE = 0.009;          
    private static final double ADDL_MEDICARE_THRESHOLD_SINGLE = 200_000.0;

    // 401k
    private static final double K401_EMPLOYEE_LIMIT_2024 = 23_000.0;

    // Debt
    private static final double MIN_DEBT_FLOOR = 25.0;

    @PostMapping
    public ResponseEntity<?> generateBudget(@RequestBody Map<String, Object> quizData) {
        try {
            String username = (String) quizData.get("username");
            double grossYearlyIncome = Double.parseDouble(quizData.get("yearlyIncome").toString());
            double retirment = Double.parseDouble(quizData.get("401(k) Contribution").toString());
            String city = (String) quizData.get("city");
            String state = (String) quizData.get("state");
            int dependents = Integer.parseInt(quizData.get("dependents").toString());
            String spendingStyle = (String) quizData.get("spendingStyle");
            String primaryGoal        = String.valueOf(quizData.getOrDefault("primaryGoal", ""));
            String savingsPriority    = String.valueOf(quizData.getOrDefault("savingsPriority", ""));
            String housingSituation   = String.valueOf(quizData.getOrDefault("housingSituation", ""));
            String carOwnership       = String.valueOf(quizData.getOrDefault("carOwnership", ""));
            String eatingOutFrequency = String.valueOf(quizData.getOrDefault("eatingOutFrequency", ""));

            //List<String> categories = (List<String>) quizData.get("categories");
            List<String> categories = ((List<?>) quizData.getOrDefault("categories", List.of()))
                .stream()
                .map(String::valueOf)
                .collect(Collectors.toCollection(ArrayList::new));
            Map<String, Double> knownCosts = (Map<String, Double>) quizData.getOrDefault("knownCosts", Map.of());

            // Parse debt
            boolean hasDebt = Boolean.parseBoolean(String.valueOf(quizData.getOrDefault("hasDebt", false)));
            List<DebtItem> debts = parseDebts(quizData.get("debts"));

            // Get mins for debts
            Map<String, Double> debtFixed = new LinkedHashMap<>();
            for (DebtItem d : debts) {
                double minDue = computeDebtMinimum(d);
                if (minDue > 0) {
                    debtFixed.put(debtLabel(d), minDue);
                }
            }

            // Augment categories so LLM is allowed to output debt lines
            List<String> categoriesAug = new ArrayList<>(categories);
            for (DebtItem d : debts) {
                String label = debtLabel(d);
                if (!categoriesAug.contains(label)) {
                    categoriesAug.add(label);
                }
            }

            // Merge debt minimums into known costs displayed to the LLM
            Map<String, Double> knownCostsAug = new LinkedHashMap<>(knownCosts);
            for (var e : debtFixed.entrySet()) {
                // If the user already put a manual amount for the same label, keep user's amount.
                knownCostsAug.putIfAbsent(e.getKey(), e.getValue());
            }


            // String knownAllocations = knownCosts.entrySet().stream()
            //         .map(e -> String.format("- Allocate $%.2f to %s.", ((Number) e.getValue()).doubleValue(), e.getKey()))
            //         .collect(Collectors.joining("\n"));


            // String categoriesList = String.join(", ", categories);

            // Augmented list to include debts
            String knownAllocations = knownCostsAug.entrySet().stream()
            .map(e -> String.format("- Allocate $%.2f to %s.", e.getValue(), e.getKey()))
            .collect(Collectors.joining("\n"));

            String categoriesList = String.join(", ", categoriesAug);

            // Create debt text for prompt
            String debtsSection = debts.isEmpty() ? "None"
            : debts.stream().map(d -> String.format(
                "- %s | Principal: $%.2f%s%s",
                d.name,
                d.principal,
                (d.apr != null ? (", APR: " + round2(d.apr) + "%%") : ""),
                (d.dueDay != null ? (", Due Day: " + d.dueDay) : "")
            )).collect(Collectors.joining("\n"));



            // Account for 401(k) before calcuating taxes
            double k401Defferal = Math.min(grossYearlyIncome * (retirment / 100.0), K401_EMPLOYEE_LIMIT_2024);
            double taxableIncome = Math.max(0.0, grossYearlyIncome - k401Defferal);

            // Get the taxes

            double federalTax = calcTax(
                    (List<Map<String,Object>>) TAX_TABLE.get("FEDERAL_2024_SINGLE"),
                    taxableIncome);

            Map<String,Object> stateSpec =
                    (Map<String,Object>) TAX_TABLE.get(state.toUpperCase());
            double stateTax   = calcTax(stateSpec, taxableIncome);
            double fica = calcFica(grossYearlyIncome);
            double localTax = calcLocalTax(city, state, taxableIncome);

            double afterTaxYearly = taxableIncome - federalTax - stateTax - fica - localTax;
            double monthlyNet = afterTaxYearly / 12.0;

            System.out.println("Taxable Income (After 401k): " + taxableIncome);
            System.out.println("Monthly Net: " + monthlyNet);

            System.out.printf("[TAX] %s - Fed: %.2f  State(%s): %.2f  Local: %.2f fica %.2f, Net: %.2f%n",
                    username, federalTax, state, stateTax, localTax, fica, afterTaxYearly);

            double monthlyIncome = grossYearlyIncome / 12;
            double budgetCap;

            switch (spendingStyle.toLowerCase()) {
                case "low":
                    budgetCap = monthlyNet* 0.75;
                    break;
                case "medium":
                    budgetCap = monthlyNet * 0.88;
                    break;
                case "high":
                    budgetCap = monthlyNet * 0.97;
                    break;
                default:
                    budgetCap = monthlyNet * 0.85;
            }


            
            String prompt = String.format("""
            You are a financial assistant helping generate a realistic monthly budget.

            Generate a JSON object for a monthly budget for someone living in %s, %s,
            earning $%.2f **after Traditional 401(k) contriubtion, federal, state, local/municipal, and FICA (Social Security + Medicare) tax** yearly,
            supporting %d dependents, with a %s spending style.

            Their primary financial goal is: %s.
            Their savings priority is: %s.
            Housing situation: %s.
            Car ownership: %s.
            Eating-out frequency: %s.

            Use ONLY these categories: %s.

            The user already knows these costs and has requested to fix them:
            %s

            Debts (allocate at least the listed minimum for each):
            %s
            (Use the debt categories exactly as "Debt - <Name>" when allocating.)

            IMPORTANT BEHAVIOR:
            - If the primary goal is "Emergency Fund" or "Pay Down Debt", prioritize Savings and debt categories before lifestyle (Entertainment, Eating Out, Miscellaneous).
            - If the primary goal is "Maximize Investing", prioritize investment categories ("Brokerage", "Roth IRA") while still funding essentials.
            - If savings priority is "High", push more money into "Savings" and investments; if "Low", allow more lifestyle/discretionary spending.
            - Use housingSituation to tune Rent / Housing: e.g., "Renting" → normal rent; "Live with Others" → keep rent lower; "Own with Mortgage" → allow higher housing cost but keep other lifestyle categories modest.
            - Use carOwnership to adjust "Transportation" (and "Car Insurance"): "Multiple Cars" → more, "No Car" → less.
            - Use eatingOutFrequency to balance "Eating Out" vs "Groceries": "Often" → higher Eating Out but do not let it dominate the budget; "Rarely" → keep Eating Out low and shift more to Groceries.

            IMPORTANT: **Do NOT include a '401k Contribution' category in your output.** The server will append a fixed line for this.

            Use your judgment to adjust based on cost of living, dependents, and the user's chosen categories.

            You **must allocate money to all user-provided categories**, even if they are not mentioned in the rules (e.g., hobbies like "Tennis"). Make sure each category has a reasonable allocation unless it clearly shouldn't apply.

            Output format:
            {
                "Category1": amount,
                "Category2": amount,
                ...
            }

            Try to keep the total budget around $%.2f (%.0f%%%% of take-home monthly income), but this is a recommendation — the **only hard rule is that the total must not exceed the user's monthly income** ($%.2f). Round each category to whole dollars.

            Ensure that savings and investments are separated, and combined they should follow the range based on spending style and savings priority.
            """,
                city,
                state,
                afterTaxYearly,
                dependents,
                spendingStyle,
                primaryGoal,
                savingsPriority,
                housingSituation,
                carOwnership,
                eatingOutFrequency,
                categoriesList,
                knownAllocations,
                debtsSection,
                budgetCap,
                (budgetCap / monthlyNet) * 100,
                monthlyNet
            );

            // Get LLM output
            String rawResponse = openAIService.generateBudget(prompt);
            System.out.println("OpenAI response: " + rawResponse);

            // Extract clean JSON block from OpenAI response
            String jsonOnly = extractJsonBlock(rawResponse);

            // Parse response to map
            Map<String, Double> monthly = objectMapper.readValue(jsonOnly, new TypeReference<>() {});
            double k401Monthly = Math.round(k401Defferal / 12.0);
            // Making sure the LLM does not put the category itself since it only knows the percentage not the dollar amount
            monthly.remove("401k"); 
            monthly.remove("401k Contribution");
            monthly.remove("401KContribution");
            monthly.remove("401(k) Contribution");
            monthly.put("401(k) Contribution", k401Monthly);

            // Enforce debt minimums (ensure presence and at least min)
            for (var e : debtFixed.entrySet()) {
                String label = e.getKey();
                double minAmt = e.getValue();
                double existing = monthly.getOrDefault(label, 0.0);
                if (existing < minAmt) {
                    monthly.put(label, (double) round0(minAmt));
                }
            }

            Map<String, Double> weekly = new HashMap<>();
            for (Map.Entry<String, Double> entry : monthly.entrySet()) {
                weekly.put(entry.getKey(), entry.getValue() / 4.0);
            }

            // Save all 4 versions to S3
            saveToS3(username, "monthly-budget.json", monthly);
            //saveToS3(username, "monthly-budget-edited.json", monthly);
            saveToS3(username, "weekly-budget.json", weekly);
            //saveToS3(username, "weekly-budget-edited.json", weekly);

            // Add net monthly to quiz data for live tracker
            quizData.put("afterTaxYearly", round2(afterTaxYearly));
            quizData.put("monthlyNet",     round2(monthlyNet));
            quizData.put("k401Monthly", k401Monthly);

            saveQuizInput(username, quizData);
            return ResponseEntity.ok(monthly);
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.internalServerError().body("Error generating budget: " + e.getMessage());
        }
    }

    // Save the previous quiz that was submitted
    private void saveQuizInput(String username, Map<String,Object> quizData) throws Exception {
        String key      = "users/%s/last_budget_quiz.json".formatted(username);
        String json     = objectMapper.writeValueAsString(quizData);
        try (var in = new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8))) {
            s3Service.uploadFile(key, in, json.length());
        }
    }


    // Tax Helper Functions

    @SuppressWarnings("unchecked")
    private double calcTax(Object spec, double income) {
        if (spec == null) return 0.0;

        if (spec instanceof List<?> brackets) {        // FEDERAL table case
            return taxFromBrackets((List<Map<String,Object>>) brackets, income);
        }
        Map<String,Object> obj = (Map<String,Object>) spec;
        String type = ((String) obj.get("type")).toLowerCase(Locale.ROOT);

        return switch (type) {
            case "none" -> 0.0;
            case "flat" -> income * ((Number) obj.get("rate")).doubleValue();
            case "progressive" ->
                    taxFromBrackets((List<Map<String,Object>>) obj.get("brackets"), income);
            default -> 0.0;
        };
    }

    private double taxFromBrackets(List<Map<String,Object>> brackets, double income) {
        double tax = 0.0;
        double prevCap = 0.0;
        for (Map<String,Object> b : brackets) {
            Number capNum = (Number) b.get("up_to");
            double cap = capNum == null ? Double.MAX_VALUE : capNum.doubleValue();
            double rate = ((Number) b.get("rate")).doubleValue();
            if (income <= cap) {
                tax += (income - prevCap) * rate;
                break;
            } else {
                tax += (cap - prevCap) * rate;
                prevCap = cap;
            }
        }
        return tax;
    }

    // FICA - Social Security + Medicare (+ Additional Medicare over threshold)
    private double calcFica(double wages) {
        double ssTax = Math.min(wages, SS_WAGE_BASE_2024) * SS_RATE;
        double medicare = wages * MEDICARE_RATE;
        double addlMedicare = Math.max(0.0, wages - ADDL_MEDICARE_THRESHOLD_SINGLE) * ADDL_MEDICARE_RATE;
        return ssTax + medicare + addlMedicare;
    }

    // Calculate local/muniicipal taxes if the state has any
    private double calcLocalTax(String city, String state, double taxableIncome) {
        String prompt = String.format("""
        If the state has any local/Municipal taxes, 
        then use the city and state, %s, %s, 
        and the taxable yearly income, $%.2f, to calcuate it. If there is no local/Municipal tax, then just return 0.0.
        """, city, state, taxableIncome);
        String localTax = openAIService.generateResponseLocalTaxes(prompt);
        System.out.println("Local Tax: " + localTax);
        return Double.parseDouble(localTax);

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

    // Debt Helper Functions
    private static class DebtItem {
        final String name;
        final double principal;
        final Double apr;        // percent, nullable
        final Double minMonthly; // nullable
        final Integer dueDay;    // nullable

        DebtItem(String name, double principal, Double apr, Double minMonthly, Integer dueDay) {
            this.name = name;
            this.principal = principal;
            this.apr = apr;
            this.minMonthly = minMonthly;
            this.dueDay = dueDay;
        }
    }

    @SuppressWarnings("unchecked")
    private List<DebtItem> parseDebts(Object raw) {
        if (!(raw instanceof List<?> list)) return List.of();
        List<DebtItem> out = new ArrayList<>();
        for (Object o : list) {
            if (!(o instanceof Map<?,?> m)) continue;
            Object nameObj = m.get("name");
            String name = (nameObj == null ? "" : String.valueOf(nameObj)).trim();
            if (name.isEmpty()) continue;

            double principal = parseDoubleSafe(m.get("principal"));
            Double apr = toNullableDouble(m.get("apr"));
            Double minMonthly = toNullableDouble(m.get("minMonthly"));
            Integer dueDay = toNullableInt(m.get("dueDay"));

            out.add(new DebtItem(name, principal, apr, minMonthly, dueDay));
        }
        return out;
    }

    private double computeDebtMinimum(DebtItem d) {
        if (d.minMonthly != null && d.minMonthly > 0) {
            return round2(d.minMonthly);
        }
        if (d.apr != null && d.apr > 0 && d.principal > 0) {
            double interestOnly = d.principal * (d.apr / 100.0) / 12.0;
            return round2(Math.max(MIN_DEBT_FLOOR, interestOnly));
        }
        return 0.0;
    }

    private static String debtLabel(DebtItem d) {
        return "Debt - " + d.name;
    }

    private static double parseDoubleSafe(Object o) {
        if (o == null) return 0.0;
        try { return Double.parseDouble(String.valueOf(o).replaceAll(",", "")); }
        catch (Exception e) { return 0.0; }
    }
    private static Double toNullableDouble(Object o) {
        if (o == null) return null;
        String s = String.valueOf(o).replace("%","").trim();
        if (s.isEmpty()) return null;
        try { return Double.parseDouble(s); } catch (Exception e) { return null; }
    }
    private static Integer toNullableInt(Object o) {
        if (o == null) return null;
        String s = String.valueOf(o).trim();
        if (s.isEmpty()) return null;
        try { return Integer.parseInt(s); } catch (Exception e) { return null; }
    }
    private static double round2(double v) { return Math.round(v * 100.0) / 100.0; }
    private static long round0(double v) { return Math.round(v); }

   
  

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
    // Get previous quiz
    @GetMapping("/last/{username}")
    public ResponseEntity<?> lastQuiz(@PathVariable String username) {
        try {
            String key   = "users/%s/last_budget_quiz.json".formatted(username);
            byte[] bytes = s3Service.downloadFile(key);
            String json  = new String(bytes, StandardCharsets.UTF_8);
            return ResponseEntity.ok(objectMapper.readTree(json)); 
        } catch (Exception e) {
            // nothing saved yet 
            return ResponseEntity.noContent().build();
        }
    }

}