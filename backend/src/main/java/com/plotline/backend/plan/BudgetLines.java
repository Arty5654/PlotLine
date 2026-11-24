package com.plotline.backend.plan;

import java.util.Locale;

/**
 * The budget lines Budget → Plan shares with the budget:
 *   "Emergency Fund"       what goes to the emergency fund each month (while it isn't full)
 *   "Savings - <goal>"     what goes to each savings goal
 *   "Savings"              savings for anything else (what's left after the fund and goals)
 *   "Debt - <debt>"        a debt's minimum payment (exactly the payoff planner's minimum)
 *   "Extra Debt Payment"   the payoff planner's extra each month, on top of the minimums
 * All of them are money set aside or paid down, never spending.
 */
public final class BudgetLines {
    private BudgetLines() { }

    public static final String SAVINGS = "Savings";
    public static final String EMERGENCY_FUND = "Emergency Fund";
    public static final String EXTRA_DEBT = "Extra Debt Payment";
    public static final String GOAL_PREFIX = "Savings - ";
    public static final String DEBT_PREFIX = "Debt - ";

    public static String goal(String name) { return GOAL_PREFIX + name.strip(); }
    public static String debt(String name) { return DEBT_PREFIX + name.strip(); }

    private static String key(String line) { return line == null ? "" : line.strip().toLowerCase(Locale.ROOT); }

    public static boolean isGoal(String line) { return key(line).startsWith(GOAL_PREFIX.toLowerCase(Locale.ROOT)); }
    public static boolean isDebt(String line) { return key(line).startsWith(DEBT_PREFIX.toLowerCase(Locale.ROOT)); }
    public static boolean isExtraDebt(String line) { return key(line).equals(EXTRA_DEBT.toLowerCase(Locale.ROOT)); }

    /** a goal line or the extra debt payment: counted with savings (the 20% in 50/30/20) */
    public static boolean isPlanSaving(String line) { return isGoal(line) || isExtraDebt(line); }
}
