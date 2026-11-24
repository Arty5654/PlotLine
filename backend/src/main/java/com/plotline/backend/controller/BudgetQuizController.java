package com.plotline.backend.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.BudgetQuizRequest;
import com.plotline.backend.dto.BudgetRequest;
import com.plotline.backend.tax.TakeHomeCalculator;
import com.plotline.backend.service.OpenAIService;
import com.plotline.backend.service.S3Service;
import static com.plotline.backend.util.UsernameUtils.normalize;
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
    private static final Logger log = LoggerFactory.getLogger(BudgetQuizController.class);


    @Autowired
    private OpenAIService openAIService;

    @Autowired
    private S3Service s3Service;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Autowired
    private com.plotline.backend.categorize.Categorizer categorizer;

    @Autowired
    private com.plotline.backend.service.FixedCosts fixedCosts;

    @Autowired
    private com.plotline.backend.service.BudgetChanges budgetChanges;

    // the budget as it is now: goal amounts set in Plan carry over
    @Autowired
    private com.plotline.backend.plan.BudgetFiles budgetFiles;

    // take-home pay with the current year's tax rules (shared with the paycheck calculator)
    @Autowired
    private TakeHomeCalculator takeHome;

    // Debt
    private static final double MIN_DEBT_FLOOR = 25.0;

    @PostMapping
    public ResponseEntity<?> generateBudget(@RequestBody Map<String, Object> quizData) {
        try {
            String username = normalize((String) quizData.get("username"));
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
            Map<String, Double> knownCosts = new LinkedHashMap<>(toDoubleMap(quizData.get("knownCosts")));

            // rent/roommates/utilities, the commute, and insurance taken out of the paycheck
            QuizDetails details = QuizDetails.from(quizData);
            // Regenerate on the budget page: exactly its categories (lines they removed there stay removed)
            boolean exact = Boolean.TRUE.equals(quizData.get("exactCategories"));
            Set<String> requested = new HashSet<>(categories);
            details.applyTo(categories, knownCosts);
            // amounts changed on the review screen before "Rebuild with AI": they stay exactly as typed
            Map<String, Double> overrides = toDoubleMap(quizData.get("reviewOverrides"));
            overrides.forEach((category, amount) -> {
                if (amount == null || is401kKey(category)) return;
                knownCosts.put(category, amount);
                if (!category.startsWith("Debt - ") && !categories.contains(category)) categories.add(category);
                requested.add(category);
            });
            if (exact) {
                categories.removeIf(c -> !requested.contains(c));
                knownCosts.keySet().removeIf(c -> !requested.contains(c) && !c.startsWith("Debt - "));
            }
            // categories just added on the budget page: sized from real spending, not from what's left over
            List<String> added = toStringList(quizData.get("newCategories"));
            String addedNote = added.isEmpty() ? "" : "\n- They just added these categories: " + String.join(", ", added)
                    + ". Estimate each from what they really spend (their transactions, if listed) or a typical amount for someone like them."
                    + " Don't size them to fill leftover money. The total still has to fit their take-home: lower flexible categories to make room.";

            // Parse debt
            boolean hasDebt = Boolean.parseBoolean(String.valueOf(quizData.getOrDefault("hasDebt", false)));
            List<DebtItem> debts = parseDebts(quizData.get("debts"));

            // Get mins for debts
            Map<String, Double> debtFixed = new LinkedHashMap<>();
            java.time.LocalDate today = java.time.LocalDate.now();
            for (DebtItem d : debts) {
                if (d.startsLater(today)) continue; // no payment this month yet: the app reminds them before it starts
                double minDue = computeDebtMinimum(d);
                if (minDue > 0) {
                    debtFixed.put(debtLabel(d), minDue);
                }
            }

            // Augment categories so LLM is allowed to output debt lines
            List<String> categoriesAug = new ArrayList<>(categories);
            for (DebtItem d : debts) {
                if (d.startsLater(today)) continue;
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
            // the payoff planner's extra each month, on top of the minimums: its own line, as set there
            double plannedExtra = Math.round(parseDoubleSafe(quizData.get("extraDebtPayment")));
            String extraLine = com.plotline.backend.plan.BudgetLines.EXTRA_DEBT;
            if (plannedExtra > 0 && !debtFixed.isEmpty()) {
                knownCostsAug.putIfAbsent(extraLine, plannedExtra);
                if (!categoriesAug.contains(extraLine)) categoriesAug.add(extraLine);
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
                "- %s | Principal: $%.2f%s%s%s",
                d.name,
                d.principal,
                (d.apr != null ? (", APR: " + round2(d.apr) + "%") : ""), // an argument, not the format: one %
                (d.dueDay != null ? (", Due Day: " + d.dueDay) : ""),
                (d.startsLater(today) ? ", payments don't start until " + d.nextDue + " (do NOT budget for it this month)" : "")
            )).collect(Collectors.joining("\n"));



            // 401(k) and taxes with the current year's rules (the standard deduction and the state's
            // deductions are taken off first; this used 2024 tables without them)
            TakeHomeCalculator.Result pay = takeHome.calculate(grossYearlyIncome,
                    takeHome.knowsState(state) ? state : takeHome.stateCode(state), retirment, details.insuranceYearly());
            double k401Defferal = pay.k401();
            double taxableIncome = Math.max(0.0, grossYearlyIncome - k401Defferal);
            double federalTax = pay.federalTax();
            double stateTax = pay.stateTax();
            double fica = pay.socialSecurity() + pay.medicare();
            double localTax = calcLocalTax(city, state, taxableIncome);

            double afterTaxYearly = pay.takeHome() - localTax;
            double monthlyNet = afterTaxYearly / 12.0;

            log.debug("Taxable Income (After 401k): {}", taxableIncome);
            log.debug("Monthly Net: {}", monthlyNet);

            log.debug(String.format("[TAX] %s - Fed: %.2f  State(%s): %.2f  Local: %.2f fica %.2f, Net: %.2f",
                    username, federalTax, state, stateTax, localTax, fica, afterTaxYearly));

            double monthlyIncome = grossYearlyIncome / 12;
            BudgetingStyle style = BudgetingStyle.from(quizData);
            double budgetCap = monthlyNet * style.share(spendingStyle);


            
            String prompt = String.format("""
            You are a financial assistant helping generate a realistic monthly budget.

            Generate a JSON object for a monthly budget for someone living in %s, %s,
            earning $%.2f **after Traditional 401(k) contriubtion, federal, state, local/municipal, and FICA (Social Security + Medicare) tax** yearly,
            supporting %d dependents.
            How they like to budget: %s

            Their primary financial goal is: %s.
            Their savings priority is: %s.
            Housing situation: %s.
            Car ownership: %s.
            Eating-out frequency: %s.
            %s

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
            - If the user already knows some costs and has requested to fix them, please adjust the rest of the budget accordingly to not create a budget that is over budget.

            IMPORTANT: **Do NOT include a '401k Contribution' category in your output.** The server will append a fixed line for this.

            Use your judgment to adjust based on cost of living, dependents, and the user's chosen categories.

            You **must allocate money to all user-provided categories**, even if they are not mentioned in the rules (e.g., hobbies like "Tennis"). Make sure each category has a reasonable allocation unless it clearly shouldn't apply.

            Output format (JSON only):
            {
                "budget": {"Category1": amount, "Category2": amount, ...},
                "why": {"Category1": "one short plain sentence: why this amount, naming what it's based on (e.g. 2 people, cooks most nights, Virginia prices)", ...}
            }

            Try to keep the total budget around $%.2f (%.0f%% of take-home monthly income), but this is a recommendation — the **only hard rule is that the total must not exceed the user's monthly income** ($%.2f). Round each category to whole dollars.

            Ensure that savings and investments are separated, and combined they should follow how they like to budget and their savings priority.
            """,
                city,
                state,
                afterTaxYearly,
                dependents,
                style.rules(monthlyNet),
                primaryGoal,
                savingsPriority,
                housingSituation,
                carOwnership,
                eatingOutFrequency,
                details.promptNotes() + addedNote,
                categoriesList,
                knownAllocations,
                debtsSection,
                budgetCap,
                (budgetCap / monthlyNet) * 100,
                monthlyNet
            );

            // Get LLM output
            String rawResponse = openAIService.generateBudget(prompt);
            log.debug("OpenAI response: {}", rawResponse);

            // Extract clean JSON block from OpenAI response
            String jsonOnly = extractJsonBlock(rawResponse);

            // {"budget": {...}, "why": {...}} (or just the amounts)
            com.fasterxml.jackson.databind.JsonNode answer = objectMapper.readTree(jsonOnly);
            com.fasterxml.jackson.databind.JsonNode amounts = answer.has("budget") ? answer.get("budget") : answer;
            Map<String, Double> monthly = new LinkedHashMap<>();
            amounts.fields().forEachRemaining(e -> { if (e.getValue().isNumber()) monthly.put(e.getKey(), e.getValue().asDouble()); });
            Map<String, String> why = new LinkedHashMap<>();
            answer.path("why").fields().forEachRemaining(e -> why.put(e.getKey(), e.getValue().asText()));
            double k401Monthly = Math.round(k401Defferal / 12.0);
            // Making sure the LLM does not put the category itself since it only knows the percentage not the dollar amount
            monthly.remove("401k"); 
            monthly.remove("401k Contribution");
            monthly.remove("401KContribution");
            monthly.remove("401(k) Contribution");

            // Enforce debt minimums (ensure presence and at least min)
            for (var e : debtFixed.entrySet()) {
                String label = e.getKey();
                double minAmt = e.getValue();
                double existing = monthly.getOrDefault(label, 0.0);
                if (existing < minAmt) {
                    monthly.put(label, (double) round0(minAmt));
                }
            }

            // known costs are fixed: the AI can't change them (debts only have a minimum: paying more is allowed)
            for (var e : knownCostsAug.entrySet()) {
                if (e.getKey().startsWith("Debt - ")) continue;
                if (monthly.containsKey(e.getKey()) || categoriesAug.contains(e.getKey())) monthly.put(e.getKey(), (double) round0(e.getValue()));
            }
            // a debt line is its minimum (what the payoff planner shows); paying more is Extra Debt Payment
            boolean extraTyped = knownCostsAug.containsKey(extraLine);
            for (var e : debtFixed.entrySet()) {
                if (overrides.containsKey(e.getKey())) continue; // typed on the review screen: kept
                double minimum = round0(e.getValue()), now = monthly.getOrDefault(e.getKey(), 0.0);
                if (now - minimum < 1) continue;
                monthly.put(e.getKey(), minimum);
                monthly.merge(extraTyped ? "Savings" : extraLine, (double) round0(now - minimum), Double::sum);
                if (!extraTyped) why.put(extraLine, "Paying more than the minimums gets you out of debt sooner.");
            }
            // at least what driving and the commute cost (Gas, Transportation); the AI may plan more
            if (details.splitsCommute()) monthly.remove("Commute"); // it's in Gas and Transportation
            // Regenerate: only the page's categories, even if the AI adds others
            if (exact) monthly.keySet().removeIf(c -> !categoriesAug.contains(c) && !knownCostsAug.containsKey(c));
            // Gas and Transportation say exactly what they cover (the AI's explanations were vague)
            details.drivingWhy().forEach((line, text) -> { if (monthly.containsKey(line)) why.put(line, text); });
            for (var e : details.minimums().entrySet()) {
                if (!categoriesAug.contains(e.getKey())) continue; // a line they removed stays removed
                if (monthly.getOrDefault(e.getKey(), 0.0) < e.getValue()) monthly.put(e.getKey(), (double) Math.round(Math.ceil(e.getValue())));
            }
            // never more than they bring home: the AI sometimes plans more (from high real spending)
            Set<String> lockedLines = new HashSet<>(knownCostsAug.keySet());
            lockedLines.addAll(details.minimums().keySet());
            double savingsFloor = switch (style.kind()) {
                case "payYourselfFirst" -> monthlyNet * style.savePercent() / 100;
                case "fiftyThirtyTwenty" -> monthlyNet * 0.20;
                default -> 0;
            };
            Map<String, Double> lowered = BudgetFit.fit(monthly, monthlyNet, lockedLines, savingsFloor);
            lowered.forEach((line, was) -> why.merge(line, "Lowered to fit your take-home (was $" + Math.round(was) + ").",
                    (a, b) -> a + " " + b));
            // "every dollar assigned": whatever is left goes to Savings
            if (style.assignsEverything()) {
                double total = monthly.values().stream().mapToDouble(Double::doubleValue).sum();
                if (monthlyNet - total >= 1) monthly.merge("Savings", (double) Math.round(monthlyNet - total), Double::sum);
            }
            // Savings split into the emergency fund and goals from the Plan tab
            SavingsSplit.apply(monthly, why, details.savings(), lockedLines, budgetFiles.monthly(username));
            if (extraTyped && monthly.containsKey(extraLine))
                why.put(extraLine, "The extra each month from your debt payoff planner, on top of the minimums.");

            Map<String, Double> weekly = new HashMap<>();
            for (Map.Entry<String, Double> entry : monthly.entrySet()) {
                weekly.put(entry.getKey(), entry.getValue() / 4.0);
            }

            // Add net monthly to quiz data for live tracker
            quizData.put("afterTaxYearly", round2(afterTaxYearly));
            quizData.put("monthlyNet",     round2(monthlyNet));
            quizData.put("k401Monthly", k401Monthly);

            if (Boolean.TRUE.equals(quizData.get("withDetails"))) {
                // the review screen: nothing is saved until they tap Save there (POST /save)
                Map<String, Object> detailed = new LinkedHashMap<>();
                detailed.put("budget", monthly);
                detailed.put("why", why);
                detailed.put("monthlyNet", round2(monthlyNet));
                detailed.put("budgetingStyle", style.kind());
                detailed.put("savePercent", style.savePercent());
                // lines the AI couldn't change (bills they told us, debt minimums): Rebalance leaves them alone
                detailed.put("fixed", knownCostsAug.keySet().stream().filter(monthly::containsKey).toList());
                // where they usually spend more than this plan, and their usual total (a warning on the review)
                detailed.put("overspending", BudgetFit.overspending(monthly, details.bankAverages()));
                double usualTotal = details.bankAverages().values().stream().mapToDouble(QuizDetails::number).sum();
                if (usualTotal > 0) detailed.put("usualTotal", Math.round(usualTotal));
                // added to the saved answers on Save, for the live tracker
                detailed.put("answers", Map.of("afterTaxYearly", round2(afterTaxYearly), "monthlyNet", round2(monthlyNet),
                        "k401Monthly", k401Monthly));
                return ResponseEntity.ok(detailed);
            }

            // older apps: saved right away
            saveToS3(username, "monthly-budget.json", monthly);
            saveToS3(username, "weekly-budget.json", weekly);
            saveQuizInput(username, quizData);
            budgetChanges.record(username);
            return ResponseEntity.ok(monthly);
        } catch (Exception e) {
            log.error("Debts failed", e);
            return ResponseEntity.internalServerError().body("Error generating budget: " + e.getMessage());
        }
    }

    // Regen Budget when new field is added (post quiz, no tax recompute)
    @PostMapping("/regen")
    public ResponseEntity<?> regenBudget(@RequestBody Map<String, Object> payload) {
        try {
            String username = normalize(String.valueOf(payload.getOrDefault("username", "")));
            if (username.isBlank()) return ResponseEntity.badRequest().body("username is required");
            String type = String.valueOf(payload.getOrDefault("type", "monthly")).toLowerCase(Locale.ROOT);
            boolean weeklyRequested = "weekly".equals(type);

            List<String> incomingCats = toStringList(payload.get("categories"));
            Map<String, Double> incomingKnown = toDoubleMap(payload.get("knownCosts"));

            Map<String, Double> result = regenBudgetInternal(username, weeklyRequested, incomingCats, incomingKnown);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.status(500).body("Failed to regenerate: " + e.getMessage());
        }
    }

    private Map<String, Double> regenBudgetInternal(String username,
                                                    boolean weeklyRequested,
                                                    List<String> incomingCats,
                                                    Map<String, Double> incomingKnown) throws Exception {
        String normUser = normalize(username);

        // Load monthlyNet + quiz categories
        Map<String,Object> quizData = readLastQuiz(normUser);
        Double monthlyNetObj = toNullableDouble(quizData.get("monthlyNet"));
        double monthlyNet = monthlyNetObj != null ? monthlyNetObj : 0.0;
        List<String> quizCats = toStringList(quizData.get("categories"));

        // Load current budget (edited preferred)
        Map<String, Double> current = loadBudget(normUser, weeklyRequested ? "weekly" : "monthly");
        Map<String, Double> currentMonthly = weeklyRequested ? multiplyMap(current, 4.0) : current;

        // Merge categories
        Set<String> mergedCats = new LinkedHashSet<>();
        mergedCats.addAll(currentMonthly.keySet());
        mergedCats.addAll(quizCats);
        mergedCats.addAll(incomingCats);

        // Known costs baseline from current budget, override with incoming numeric (convert weekly->monthly if needed)
        Map<String, Double> known = new LinkedHashMap<>(currentMonthly);
        incomingKnown.forEach((k,v) -> {
            if (v != null) known.put(k, weeklyRequested ? v * 4.0 : v);
        });

        // Strip 401k keys from known
        known.keySet().removeIf(this::is401kKey);

        // Fallback monthlyNet
        if (monthlyNet <= 0) {
            monthlyNet = known.values().stream().mapToDouble(Double::doubleValue).sum();
        }

        String categoriesList = String.join(", ", mergedCats);
        String knownAllocations = known.entrySet().stream()
                .map(e -> String.format("- Allocate $%.2f to %s.", e.getValue(), e.getKey()))
                .collect(Collectors.joining("\n"));

        String prompt = String.format("""
            You are a financial assistant regenerating a monthly budget.

            Use ONLY these categories: %s.
            Fixed/known amounts (do not change):
            %s

            Any category not listed in known amounts must still get a reasonable allocation > 0.
            Do NOT include 401k/401(k) lines.

            Output JSON:
            {
              "Category1": amount,
              "Category2": amount
            }

            Total must NOT exceed $%.2f. Allocate to every category.
            """, categoriesList, knownAllocations, monthlyNet);

        String raw = openAIService.generateBudget(prompt);
        String jsonOnly = extractJsonBlock(raw);
        Map<String, Double> monthly = objectMapper.readValue(jsonOnly, new TypeReference<>() {});

        // Cleanup and enforce
        monthly.keySet().removeIf(this::is401kKey);
        enforceAllCategories(monthly, new ArrayList<>(mergedCats), monthlyNet);

        // Save monthly & weekly
        Map<String, Double> weekly = divideMap(monthly, 4.0);
        saveToS3(normUser, "monthly-budget.json", monthly);
        saveToS3(normUser, "weekly-budget.json", weekly);

        return weeklyRequested ? weekly : monthly;
    }

    // Save the previous quiz that was submitted
    private void saveQuizInput(String username, Map<String,Object> quizData) throws Exception {
        String normUser = normalize(username);
        String key      = "users/%s/last_budget_quiz.json".formatted(normUser);
        String json     = objectMapper.writeValueAsString(quizData);
        try (var in = new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8))) {
            s3Service.uploadFile(key, in, json.length());
        }
    }


    // Calculate local/muniicipal taxes if the state has any
    private double calcLocalTax(String city, String state, double taxableIncome) {
        String prompt = String.format("""
        If the state has any local/Municipal taxes, 
        then use the city and state, %s, %s, 
        and the taxable yearly income, $%.2f, to calcuate it. If there is no local/Municipal tax, then just return 0.0.
        """, city, state, taxableIncome);
        String localTax = openAIService.generateResponseLocalTaxes(prompt);
        log.debug("Local Tax: {}", localTax);
        return Double.parseDouble(localTax);

    }

    private void saveToS3(String username, String fileName, Map<String, Double> budget) throws Exception {
        String normUser = normalize(username);
        String key = "users/" + normUser + "/" + fileName;
        String jsonData = objectMapper.writeValueAsString(budget);
        ByteArrayInputStream stream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));
        s3Service.uploadFile(key, stream, jsonData.length());
    }

    private String extractJsonBlock(String text) {
      int start = text.indexOf('{');
      int end = text.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
          String json = text.substring(start, end + 1);
          // Remove commas from numbers (e.g., "1,200" -> "1200")
          // Pattern: digit, comma, digit(s) - replace comma with nothing
          json = json.replaceAll("(\\d),(\\d)", "$1$2");
          return json;
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
        final java.time.LocalDate nextDue; // nullable: the next payment date from the app

        DebtItem(String name, double principal, Double apr, Double minMonthly, Integer dueDay, java.time.LocalDate nextDue) {
            this.name = name;
            this.principal = principal;
            this.apr = apr;
            this.minMonthly = minMonthly;
            this.dueDay = dueDay != null ? dueDay : nextDue != null ? nextDue.getDayOfMonth() : null;
            this.nextDue = nextDue;
        }

        /** a loan whose first payment is more than ~6 weeks away (e.g. a new grad's grace period) */
        boolean startsLater(java.time.LocalDate today) {
            return nextDue != null && nextDue.isAfter(today.plusDays(45));
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
            // the app sends "minPayment" and "dueDate"; older saved quizzes may have "minMonthly"/"dueDay"
            Double minMonthly = toNullableDouble(m.get("minPayment") != null ? m.get("minPayment") : m.get("minMonthly"));
            Integer dueDay = toNullableInt(m.get("dueDay"));
            java.time.LocalDate nextDue = parseDay(m.get("dueDate"));

            out.add(new DebtItem(name, principal, apr, minMonthly, dueDay, nextDue));
        }
        return out;
    }

    /** "2026-12-01T05:00:00Z" or "2026-12-01" → the day (null if missing or unreadable) */
    static java.time.LocalDate parseDay(Object value) {
        if (value == null) return null;
        String text = String.valueOf(value).strip();
        try {
            return java.time.OffsetDateTime.parse(text).toLocalDate();
        } catch (Exception e) {
            try {
                return java.time.LocalDate.parse(text.length() >= 10 ? text.substring(0, 10) : text);
            } catch (Exception ignored) {
                return null;
            }
        }
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

    private Map<String, Double> toDoubleMap(Object raw) {
        if (!(raw instanceof Map<?,?> m)) return Map.of();
        Map<String, Double> out = new LinkedHashMap<>();
        for (var e : m.entrySet()) {
            String key = String.valueOf(e.getKey());
            Double val = toNullableDouble(e.getValue());
            if (val != null) {
                out.put(key, val);
            }
        }
        return out;
    }

    private List<String> toStringList(Object raw) {
        if (!(raw instanceof List<?> list)) return List.of();
        return list.stream().map(String::valueOf).toList();
    }

    private Map<String, Double> loadBudget(String username, String type) {
        String norm = normalize(username);
        String editedKey = "users/%s/%s-budget-edited.json".formatted(norm, type);
        String baseKey   = "users/%s/%s-budget.json".formatted(norm, type);
        try {
            byte[] data = s3Service.downloadFile(editedKey);
            return objectMapper.readValue(data, new TypeReference<>() {});
        } catch (Exception ignored) { }
        try {
            byte[] data = s3Service.downloadFile(baseKey);
            return objectMapper.readValue(data, new TypeReference<>() {});
        } catch (Exception ignored) { }
        return new LinkedHashMap<>();
    }

    private Map<String,Object> readLastQuiz(String username) throws Exception {
        String key = "users/%s/last_budget_quiz.json".formatted(username);
        byte[] bytes = s3Service.downloadFile(key);
        return objectMapper.readValue(bytes, new TypeReference<>() {});
    }

    private Map<String, Double> divideMap(Map<String, Double> src, double factor) {
        Map<String, Double> out = new LinkedHashMap<>();
        src.forEach((k,v) -> out.put(k, round2(v / factor)));
        return out;
    }

    private Map<String, Double> multiplyMap(Map<String, Double> src, double factor) {
        Map<String, Double> out = new LinkedHashMap<>();
        src.forEach((k,v) -> out.put(k, round2(v * factor)));
        return out;
    }

    private boolean is401kKey(String key) {
        if (key == null) return false;
        String lowered = key.toLowerCase(Locale.ROOT);
        return lowered.contains("401k") || lowered.contains("401(k)");
    }

    private void enforceAllCategories(Map<String, Double> monthly,
                                      List<String> categories,
                                      double monthlyNet) {
        Set<String> targetCats = categories.stream()
                .filter(c -> c != null && !c.isBlank())
                .collect(Collectors.toCollection(LinkedHashSet::new));

        double current = monthly.entrySet().stream()
                .filter(e -> e.getValue() != null && e.getValue() > 0)
                .mapToDouble(Map.Entry::getValue)
                .sum();

        List<String> missing = targetCats.stream()
                .filter(cat -> monthly.getOrDefault(cat, 0.0) <= 0.0)
                .toList();

        if (missing.isEmpty()) return;

        double remaining = monthlyNet - current;
        double fallback = remaining > 0 ? remaining / missing.size() : 1.0;
        if (fallback <= 0) fallback = 1.0;

        for (String cat : missing) {
            monthly.put(cat, round2(fallback));
        }
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
          String key = String.format("users/%s/%s-budget-edited.json", normalize(request.getUsername()), request.getType());
          s3Service.uploadFile(key, stream, jsonData.length());
          return ResponseEntity.ok("Edited budget saved.");
      } catch (Exception e) {
          return ResponseEntity.status(500).body("Failed to save edited budget: " + e.getMessage());
      }
  }

  /**
   * Saving after the review screen: the reviewed budget becomes the quiz's budget (what Revert goes
   * back to) and the current budget (the "-edited" copy everything else reads, replacing edits of
   * the old one), and the answers become the last quiz.
   * Body: {username, budget: {category: monthly amount}, answers: {...the quiz...}}
   */
  @PostMapping("/save")
  @SuppressWarnings("unchecked")
  public ResponseEntity<String> saveReviewed(@RequestBody Map<String, Object> body) {
      try {
          String username = normalize(String.valueOf(body.getOrDefault("username", "")));
          if (username.isBlank()) return ResponseEntity.badRequest().body("username is required");
          Map<String, Double> monthly = new LinkedHashMap<>(toDoubleMap(body.get("budget")));
          monthly.keySet().removeIf(this::is401kKey);
          if (monthly.isEmpty()) return ResponseEntity.badRequest().body("budget is required");
          Map<String, Object> answers = body.get("answers") instanceof Map<?, ?> a
                  ? new LinkedHashMap<>((Map<String, Object>) a) : new LinkedHashMap<>();
          answers.put("username", username);
          answers.remove("withDetails");
          answers.remove("reviewOverrides");

          Map<String, Double> weekly = new LinkedHashMap<>();
          monthly.forEach((k, v) -> weekly.put(k, v / 4.0));
          saveToS3(username, "monthly-budget.json", monthly);
          saveToS3(username, "weekly-budget.json", weekly);
          // the same format POST /api/budget saves (the weekly recap, goals, tuning and bank sorting read it)
          for (var copy : Map.of("monthly", monthly, "weekly", weekly).entrySet()) {
              byte[] json = objectMapper.writeValueAsBytes(new BudgetRequest(username, copy.getKey(), copy.getValue()));
              s3Service.uploadFile("users/%s/%s-budget-edited.json".formatted(username, copy.getKey()), new ByteArrayInputStream(json), json.length);
          }
          categorizer.clearCategoryCache(username); // bank transactions sort into the new categories
          fixedCosts.applyQuizBudget(username, monthly); // savings, bills, subscriptions, debt minimums
          budgetChanges.record(username);
          saveQuizInput(username, answers);
          return ResponseEntity.ok("Budget saved.");
      } catch (Exception e) {
          log.error("Saving the reviewed budget failed", e);
          return ResponseEntity.internalServerError().body("Couldn't save your budget.");
      }
  }

  // Revert edited budget to original
  @PostMapping("/revert/{username}/{type}")
  public ResponseEntity<String> revertToOriginal(@PathVariable String username, @PathVariable String type) {
    try {
        String editedKey = String.format("users/%s/%s-budget-edited.json", normalize(username), type);
        s3Service.deleteFile(editedKey);
        budgetChanges.record(normalize(username));
        return ResponseEntity.ok("Reverted to original budget.");
    } catch (Exception e) {
        return ResponseEntity.status(500).body("Failed to revert: " + e.getMessage());
    }
  }
    // Get previous quiz
    @GetMapping("/last/{username}")
    public ResponseEntity<?> lastQuiz(@PathVariable String username) {
        try {
            String normUser = normalize(username);
            String key   = "users/%s/last_budget_quiz.json".formatted(normUser);
            byte[] bytes = s3Service.downloadFile(key);
            String json  = new String(bytes, StandardCharsets.UTF_8);
            return ResponseEntity.ok(objectMapper.readTree(json)); 
        } catch (Exception e) {
            // Legacy fallback with original casing
            try {
                String key   = "users/%s/last_budget_quiz.json".formatted(username);
                byte[] bytes = s3Service.downloadFile(key);
                String json  = new String(bytes, StandardCharsets.UTF_8);
                return ResponseEntity.ok(objectMapper.readTree(json)); 
            } catch (Exception ignored) {
                return ResponseEntity.noContent().build();
            }
        }
    }

}
