package com.plotline.backend.investing;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.springframework.stereotype.Component;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.controller.BudgetFit;
import com.plotline.backend.dto.SavedPortfolio;
import com.plotline.backend.dto.SavedPortfolio.AccountType;
import com.plotline.backend.plan.BudgetFiles;
import com.plotline.backend.service.PortfolioService;
import com.plotline.backend.service.S3Service;
import com.plotline.backend.tax.TakeHomeCalculator;

/**
 * What PlotLine already knows that the investing quiz uses, so it asks less and advises better:
 * income and 401(k) from the budget quiz, the account's budget line, the Plan's emergency fund and
 * high-interest debts, what the other account holds, and last time's answers.
 */
@Component
public class InvestorFacts {

    /** debts at or above this APR (percent) are worth paying down before investing */
    static final double HIGH_APR = 8;

    /** answers both quizzes ask: carried over from the other account's quiz the first time */
    static final Set<String> SHARED = Set.of("age", "experience", "dropReaction", "style", "esg");

    /**
     * @param yearlyIncome   gross, from the budget quiz (null: unknown)
     * @param k401Yearly     pre-tax 401(k) a year
     * @param monthlyAmount  the account's budget line ("Roth IRA" / "Brokerage")
     * @param federalBracket percent, single filer (null: income unknown)
     * @param emergencySaved -1 when a linked account holds it (the app sends its balance)
     * @param emergencyTarget months × monthly spending (0: no budget yet)
     * @param otherHoldings  tickers in the other account's portfolio
     * @param otherMonthly   the other account's budget line
     * @param answers        last time's answers for this account (or the other's shared ones)
     */
    public record Facts(Double yearlyIncome, double k401Yearly, double monthlyAmount, Integer federalBracket,
                        double emergencySaved, double emergencyTarget, int emergencyMonths,
                        List<Debt> highInterestDebts, List<String> otherHoldings, double otherMonthly,
                        Map<String, String> answers, Ira ira) { }

    public record Debt(String name, double apr, double balance) { }

    public record Ira(int year, double limit, int catchUpAge, double catchUp,
                      List<Double> rothSingle, List<Double> rothJoint) { }

    private static final Pattern TICKER = Pattern.compile("\\*\\*([A-Z][A-Z.]{0,9})(?:\\*\\*|\\s*-)");

    private final S3Service s3;
    private final BudgetFiles budgets;
    private final PortfolioService portfolios;
    private final TakeHomeCalculator tax;
    private final ObjectMapper json = new ObjectMapper();

    public InvestorFacts(S3Service s3, BudgetFiles budgets, PortfolioService portfolios, TakeHomeCalculator tax) {
        this.s3 = s3;
        this.budgets = budgets;
        this.portfolios = portfolios;
        this.tax = tax;
    }

    public static String budgetLine(AccountType account) {
        return account == AccountType.ROTH_IRA ? "Roth IRA" : "Brokerage";
    }

    static AccountType other(AccountType account) {
        return account == AccountType.ROTH_IRA ? AccountType.BROKERAGE : AccountType.ROTH_IRA;
    }

    public Facts load(String user, AccountType account) {
        Map<String, Object> quiz = read("users/%s/last_budget_quiz.json".formatted(user));
        Double income = number(quiz.get("yearlyIncome"));
        Double k401Monthly = number(quiz.get("k401Monthly"));
        double k401 = k401Monthly == null ? 0 : k401Monthly * 12;

        Map<String, Double> budget = budgets.monthly(user);
        double spending = budget.entrySet().stream().filter(e -> !BudgetFit.isSaving(e.getKey()))
                .mapToDouble(Map.Entry::getValue).sum();

        JsonNode plan = tree("users/%s/plan.json".formatted(user));
        JsonNode fund = plan.path("emergencyFund");
        int months = fund.path("months").asInt(3);
        List<Debt> debts = new ArrayList<>();
        for (JsonNode d : plan.path("debts")) {
            double apr = d.path("apr").asDouble(), balance = d.path("balance").asDouble();
            if (apr >= HIGH_APR && balance > 0) debts.add(new Debt(d.path("name").asText("A debt"), apr, balance));
        }
        debts.sort((a, b) -> Double.compare(b.apr(), a.apr()));

        JsonNode ira = tax.ira();
        Ira limits = new Ira(tax.year(), ira.path("limit").asDouble(), ira.path("catchUpAge").asInt(50),
                ira.path("catchUp").asDouble(), pair(ira.path("rothPhaseout").path("single")),
                pair(ira.path("rothPhaseout").path("joint")));

        return new Facts(income, k401, line(budget, budgetLine(account)),
                income == null ? null : tax.federalBracket(income, k401),
                linked(fund) ? -1 : fund.path("saved").asDouble(0), Math.round(spending * months), months, debts,
                holdings(user, other(account)), line(budget, budgetLine(other(account))),
                savedAnswers(user, account), limits);
    }

    // ---------- answers (users/{u}/portfolio/{account}/quiz.json) ----------

    private static String answersKey(String user, AccountType account) {
        return "users/%s/portfolio/%s/quiz.json".formatted(user, account.name().toLowerCase());
    }

    /** this account's answers from last time, else the other quiz's shared ones (age, experience...) */
    Map<String, String> savedAnswers(String user, AccountType account) {
        Map<String, String> mine = strings(read(answersKey(user, account)));
        if (!mine.isEmpty()) return mine;
        Map<String, String> shared = new LinkedHashMap<>();
        strings(read(answersKey(user, other(account)))).forEach((k, v) -> { if (SHARED.contains(k)) shared.put(k, v); });
        return shared;
    }

    public void saveAnswers(String user, AccountType account, Map<String, String> answers) {
        Map<String, String> keep = new LinkedHashMap<>(answers);
        keep.remove("username");
        keep.remove("account");
        try {
            byte[] bytes = json.writeValueAsBytes(keep);
            s3.uploadFile(answersKey(user, account), new java.io.ByteArrayInputStream(bytes), bytes.length);
        } catch (Exception ignored) {
            // answers only prefill the next quiz
        }
    }

    // ---------- helpers ----------

    private List<String> holdings(String user, AccountType account) {
        SavedPortfolio p = portfolios.loadEditedPortfolio(user, account);
        if (p == null) p = portfolios.loadOriginalPortfolio(user, account);
        return p == null ? List.of() : tickers(p.getPortfolio());
    }

    static List<String> tickers(String text) {
        Set<String> out = new LinkedHashSet<>();
        if (text != null) {
            Matcher m = TICKER.matcher(text);
            while (m.find()) out.add(m.group(1));
        }
        return List.copyOf(out);
    }

    private static double line(Map<String, Double> budget, String name) {
        return budget.entrySet().stream().filter(e -> e.getKey().equalsIgnoreCase(name))
                .mapToDouble(Map.Entry::getValue).findFirst().orElse(0);
    }

    private static boolean linked(JsonNode fund) {
        JsonNode id = fund.path("linkedAccountId");
        return id.isTextual() && !id.asText().isBlank();
    }

    private static List<Double> pair(JsonNode n) {
        return n.isArray() && n.size() == 2 ? List.of(n.get(0).asDouble(), n.get(1).asDouble()) : List.of();
    }

    private static Double number(Object o) {
        if (o instanceof Number n) return n.doubleValue();
        try { return o == null ? null : Double.parseDouble(o.toString()); } catch (NumberFormatException e) { return null; }
    }

    private static Map<String, String> strings(Map<String, Object> m) {
        Map<String, String> out = new LinkedHashMap<>();
        m.forEach((k, v) -> { if (v != null) out.put(k, v.toString()); });
        return out;
    }

    private Map<String, Object> read(String key) {
        try {
            byte[] data = s3.downloadFile(key);
            if (data == null || data.length == 0) return Map.of();
            return json.readValue(data, new TypeReference<Map<String, Object>>() {});
        } catch (Exception e) {
            return Map.of();
        }
    }

    private JsonNode tree(String key) {
        try {
            byte[] data = s3.downloadFile(key);
            return data == null || data.length == 0 ? json.createObjectNode() : json.readTree(data);
        } catch (Exception e) {
            return json.createObjectNode();
        }
    }
}
