package com.plotline.backend.controller;

import java.util.Locale;
import java.util.Map;

/**
 * "How do you like to budget?" from the quiz (it replaced Spending Style: Low / Medium / High):
 *   fiftyThirtyTwenty: 50% needs, 30% wants, 20% savings and extra debt payments
 *   payYourselfFirst:  savings come out first (savePercent of take-home), spend the rest
 *   everyDollar:       every dollar of take-home has a job (anything left goes to Savings)
 *   flexible:          about 88% planned, the rest left as breathing room (the old "Medium")
 */
public record BudgetingStyle(String kind, double savePercent) {

    public static BudgetingStyle from(Map<String, Object> quiz) {
        String kind = String.valueOf(quiz.getOrDefault("budgetingStyle", "")).strip();
        double save = QuizDetails.number(quiz.get("savePercent"));
        if (save <= 0 || save > 80) save = 20;
        return new BudgetingStyle(kind.isEmpty() ? "legacy" : kind, save);
    }

    public boolean assignsEverything() {
        return kind.equals("everyDollar") || kind.equals("fiftyThirtyTwenty");
    }

    /** the share of take-home the budget should plan */
    public double share(String legacySpendingStyle) {
        return switch (kind) {
            case "fiftyThirtyTwenty", "everyDollar", "payYourselfFirst" -> 1.0;
            case "flexible" -> 0.88;
            default -> switch (legacySpendingStyle == null ? "" : legacySpendingStyle.toLowerCase(Locale.ROOT)) {
                case "low" -> 0.75;
                case "medium" -> 0.88;
                case "high" -> 0.97;
                default -> 0.85;
            };
        };
    }

    /** the instructions for the AI */
    public String rules(double monthlyNet) {
        return switch (kind) {
            case "fiftyThirtyTwenty" -> "the 50/30/20 rule. About 50%% of take-home ($%.0f) on needs (housing, utilities, groceries, transportation/commute, insurance, minimum debt payments), about 30%% ($%.0f) on wants (eating out, entertainment, shopping, subscriptions, hobbies, travel), and at least 20%% ($%.0f) on savings, investing and extra debt payments."
                    .formatted(monthlyNet * .5, monthlyNet * .3, monthlyNet * .2);
            case "payYourselfFirst" -> "pay yourself first. Savings and investing categories together get at least %.0f%% of take-home ($%.0f) before anything else; the rest is spread over spending."
                    .formatted(savePercent, monthlyNet * savePercent / 100);
            case "everyDollar" -> "every dollar assigned. The budget should add up to their whole take-home ($%.0f); anything not needed for spending goes to savings or debt.".formatted(monthlyNet);
            case "flexible" -> "flexible: plan about 88% of take-home and leave the rest unassigned as breathing room."; // not formatted: one %
            default -> "a balanced budget.";
        };
    }
}
