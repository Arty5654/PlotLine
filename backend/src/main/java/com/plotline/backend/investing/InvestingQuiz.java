package com.plotline.backend.investing;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import com.plotline.backend.dto.SavedPortfolio.AccountType;
import com.plotline.backend.investing.InvestorFacts.Facts;

/**
 * The Roth IRA and Brokerage quizzes: the "Before you invest" notes (worked out here, not by the AI,
 * so the numbers are right) and the AI prompt for each account.
 *
 * Answers (strings), both quizzes: age, experience, dropReaction (Sell / Wait / Buy more), style
 * (One fund / A few index funds / Index funds plus some stocks), esg (Yes / No), riskTolerance.
 * Roth IRA: retireAge, filingStatus (Single / Married filing jointly / Not sure), contributedThisYear,
 * workplacePlan (None / Full match / Partial match / No match / Not sure), earlyAccess (Very unlikely /
 * Possibly / Likely). Brokerage: purpose (Long-term wealth / A home / A big purchase / Extra retirement /
 * Dividend income), horizon (Under 3 years / 3-5 years / 5-10 years / 10+ years), taxBracket.
 * Older apps send goals, timeHorizon, taxPriority and withdrawalFlexibility instead; those still work.
 * The app may send emergencySaved (a linked account's balance).
 */
public final class InvestingQuiz {
    private InvestingQuiz() { }

    static String money(double amount) { return "$" + String.format(Locale.US, "%,.0f", amount); }

    private static String get(Map<String, String> a, String key) {
        String v = a.get(key);
        return v == null || v.isBlank() ? null : v.strip();
    }

    private static double number(Map<String, String> a, String key, double fallback) {
        try {
            String v = get(a, key);
            return v == null ? fallback : Double.parseDouble(v.replace("$", "").replace(",", ""));
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    /** Sell → Low, Wait → Medium, Buy more → High (the news page reads this) */
    public static String riskTolerance(Map<String, String> a) {
        String drop = get(a, "dropReaction");
        if (drop == null) return get(a, "riskTolerance") == null ? "Medium" : get(a, "riskTolerance");
        return drop.startsWith("Sell") ? "Low" : drop.startsWith("Buy") ? "High" : "Medium";
    }

    /** room left this year: the limit (plus catch-up at 50+) minus what's already in */
    static double rothRoom(Map<String, String> a, Facts f) {
        int age = (int) number(a, "age", 0);
        double limit = f.ira().limit() + (age >= f.ira().catchUpAge() ? f.ira().catchUp() : 0);
        return Math.max(0, limit - number(a, "contributedThisYear", 0));
    }

    // ---------- notes ----------

    public static List<String> notes(AccountType account, Map<String, String> a, Facts f, LocalDate today) {
        List<String> out = new ArrayList<>();
        boolean roth = account == AccountType.ROTH_IRA;

        if (roth) {
            // the yearly limit
            double room = rothRoom(a, f);
            int monthsLeft = 12 - today.getMonthValue() + 1;
            double planned = f.monthlyAmount() * monthsLeft;
            if (room <= 0) {
                out.add("You've put in this year's full " + money(f.ira().limit()) + ". Until January, your budget's Roth IRA money can go to Brokerage instead.");
            } else if (f.monthlyAmount() > 0 && planned > room + 1) {
                long months = (long) Math.floor(room / f.monthlyAmount());
                out.add("Your budget puts " + money(f.monthlyAmount()) + " a month in your Roth IRA, " + money(planned)
                        + " by December, but you can only add " + money(room) + " more in " + f.ira().year() + ". "
                        + (months > 0 ? "After about " + months + (months == 1 ? " month" : " months") + ", " : "Until January, ")
                        + "send the rest to Brokerage.");
            }

            // the income limit (MAGI ≈ salary minus a pre-tax 401(k))
            if (f.yearlyIncome() != null) {
                boolean joint = "Married filing jointly".equals(get(a, "filingStatus"));
                List<Double> range = joint ? f.ira().rothJoint() : f.ira().rothSingle();
                double magi = f.yearlyIncome() - f.k401Yearly();
                String who = joint ? "married couples filing jointly (your household's income counts)" : "single filers";
                if (range.size() == 2 && magi >= range.get(1)) {
                    out.add("At about " + money(magi) + " of income after your 401(k), you're over the Roth IRA limit for " + who
                            + " (" + money(range.get(1)) + "). You can't put money in directly; ask a tax pro about a \"backdoor\" Roth, or use Brokerage.");
                } else if (range.size() == 2 && magi > range.get(0)) {
                    out.add("At about " + money(magi) + " of income after your 401(k), you're in the range where the Roth IRA limit shrinks for "
                            + who + " (" + money(range.get(0)) + "–" + money(range.get(1)) + "), so you can put in less than "
                            + money(f.ira().limit()) + ".");
                }
            }

            // a workplace match comes first
            String plan = get(a, "workplacePlan");
            if ("Partial match".equals(plan)) {
                out.add("Get your full 401(k) match before adding to your Roth IRA. A match is free money, often a 50–100% return the day you put it in.");
            } else if ("Not sure".equals(plan)) {
                out.add("Check whether your job matches 401(k) money. If it does, get the full match before your Roth IRA.");
            }

            if ("Likely".equals(get(a, "earlyAccess"))) {
                out.add("You can take out what you put into a Roth IRA anytime, but earnings taken out before 59½ (or before the account is 5 years old) are usually taxed plus a 10% penalty. Money you'll likely need soon may fit savings or Brokerage better.");
            }
        } else {
            if ("Under 3 years".equals(get(a, "horizon"))) {
                out.add("You'll need this within 3 years. Stocks can drop 20–30% in a year, so this portfolio stays mostly in safer, cash-like funds.");
            }
            if ("Extra retirement".equals(get(a, "purpose")) && f.otherMonthly() <= 0) {
                out.add("For retirement money, a Roth IRA usually beats Brokerage: it grows tax-free. Consider adding a Roth IRA line to your budget first (up to "
                        + money(f.ira().limit()) + " a year).");
            }
        }

        // the Plan: the emergency fund, then expensive debt
        double saved = number(a, "emergencySaved", f.emergencySaved());
        if (saved >= 0 && f.emergencyTarget() > 0 && saved < f.emergencyTarget()) {
            out.add("Your emergency fund has " + money(saved) + " of its " + money(f.emergencyTarget()) + " goal ("
                    + f.emergencyMonths() + " months of spending). "
                    + (roth ? "It's best to fill it in savings before investing. In a pinch, what you put into a Roth IRA can come out without tax or penalty."
                            : "Fill it before investing money you might need soon."));
        }
        if (!f.highInterestDebts().isEmpty()) {
            InvestorFacts.Debt d = f.highInterestDebts().get(0);
            out.add("Your " + d.name() + " charges " + trim(d.apr()) + "% interest. Paying it down is a sure " + trim(d.apr())
                    + "% return, more than stocks usually earn, so consider putting extra there first.");
        }
        return out;
    }

    /** the notes as the first section of the saved portfolio text (the Why page shows it) */
    public static String notesSection(List<String> notes) {
        if (notes.isEmpty()) return "";
        StringBuilder s = new StringBuilder("### Before you invest\n\n");
        for (String n : notes) s.append("- ").append(n).append("\n\n");
        return s.toString();
    }

    private static String trim(double v) {
        return java.math.BigDecimal.valueOf(Math.round(v * 100) / 100.0).stripTrailingZeros().toPlainString();
    }

    // ---------- the prompt ----------

    /** Vanguard Target Retirement funds by year (the retirement year, rounded to the nearest 5) */
    static final Map<Integer, String> TARGET_DATE = Map.of(2030, "VTHRX", 2035, "VTTHX", 2040, "VFORX", 2045, "VTIVX",
            2050, "VFIFX", 2055, "VFFVX", 2060, "VTTSX", 2065, "VLXVX", 2070, "VSVNX");

    /** the target-date fund for a "One fund" Roth IRA ({year, ticker}), or null without an age */
    static Map.Entry<Integer, String> targetDateFund(Map<String, String> a, LocalDate today) {
        int age = (int) number(a, "age", 0), retire = (int) number(a, "retireAge", 65);
        if (age <= 0) return null;
        int year = Math.round((today.getYear() + Math.max(0, retire - age)) / 5f) * 5;
        year = Math.max(2030, Math.min(2070, year));
        return Map.entry(year, TARGET_DATE.get(year));
    }

    public static String prompt(AccountType account, Map<String, String> a, Facts f, List<String> notes, LocalDate today) {
        boolean roth = account == AccountType.ROTH_IRA;
        StringBuilder p = new StringBuilder();
        p.append(roth
                ? "Recommend a portfolio for the user's **Roth IRA** (after-tax money; qualified withdrawals are tax-free; "
                  + money(f.ira().limit()) + " a year limit in " + f.ira().year() + ").\n"
                : "Recommend a portfolio for the user's **taxable brokerage account** (no limits, money can come out anytime, "
                  + "but dividends and gains are taxed).\n");

        p.append("\nAbout them:\n");
        line(p, "Age", get(a, "age"));
        line(p, "Investing experience", get(a, "experience"));
        line(p, "If the account fell 20% in a month, they would", get(a, "dropReaction"));
        line(p, "Risk tolerance", riskTolerance(a));
        line(p, "How hands-on", get(a, "style"));
        line(p, "Prefers ESG (environmental, social, governance) funds", get(a, "esg"));
        if (f.monthlyAmount() > 0) line(p, "Monthly amount (from their budget)", money(f.monthlyAmount()) + " a month");

        if (roth) {
            int age = (int) number(a, "age", 0), retire = (int) number(a, "retireAge", 0);
            if (age > 0 && retire > age) line(p, "Plans to retire at", retire + " (about " + (retire - age) + " years, around " + (today.getYear() + retire - age) + ")");
            line(p, "Workplace 401(k)", get(a, "workplacePlan"));
            line(p, "Chance they take money out before retirement", get(a, "earlyAccess"));
        } else {
            line(p, "What the money is for", get(a, "purpose"));
            line(p, "When they'll need it", get(a, "horizon"));
            String bracket = get(a, "taxBracket");
            if ((bracket == null || bracket.equals("Not sure")) && f.federalBracket() != null) bracket = f.federalBracket() + "% (estimated from their salary)";
            line(p, "Federal tax bracket", bracket);
        }
        // older apps' answers
        line(p, "Goal", get(a, "goals"));
        line(p, "Time horizon", get(a, "timeHorizon"));
        line(p, "Tax vs flexibility", get(a, "taxPriority"));
        line(p, "Withdrawal flexibility", get(a, "withdrawalFlexibility"));

        if (!f.otherHoldings().isEmpty()) {
            line(p, "Their " + (roth ? "Brokerage account" : "Roth IRA") + " already holds", String.join(", ", f.otherHoldings())
                    + ". Make the two accounts work together (don't just repeat it; e.g. tax-inefficient holdings like bonds or REITs belong in the Roth IRA)");
        }

        p.append("\nHow to build it:\n");
        if (roth) {
            p.append("""
                    - This is long-term retirement money: lean on growth (stocks) for long horizons, and add bonds as retirement gets closer.
                    - Tax-inefficient holdings (bonds, REITs, high-dividend funds) are fine here because nothing is taxed.
                    """);
            Map.Entry<Integer, String> fund = targetDateFund(a, today);
            if ("One fund".equals(get(a, "style")) && fund != null) {
                p.append("- They chose one fund: use exactly one holding, " + fund.getValue() + " (Vanguard Target Retirement "
                        + fund.getKey() + "), at 100%. Not a total-market fund. Mention it needs $1,000 to start and rebalances itself toward bonds as "
                        + fund.getKey() + " gets closer.\n");
            }
        } else {
            p.append("""
                    - Prefer tax-efficient, low-turnover broad index ETFs; avoid funds that pay out a lot of taxable income.
                    - Match risk to when they need the money: under 3 years means mostly cash-like funds (Treasury bills, short-term Treasuries, e.g. SGOV, VGSH); 3-5 years a balanced mix; 10+ years mostly stocks.
                    - In a 32% or higher bracket, use municipal bond funds (e.g. VTEB) for the bond part; in lower brackets, regular bond funds.
                    - For "Dividend income", use a dividend ETF but explain dividends are taxed each year.
                    - For "One fund", use a single all-in-one fund (e.g. VT, or an allocation ETF like AOR / AOA).
                    """);
        }
        p.append("""
                - "One fund": 1-2 holdings. "A few index funds": 3-4. "Index funds plus some stocks": 4-5, with individual stocks at most 20% in total.
                - Prefer ETFs (no minimum to start) over mutual funds, except a target-date fund.
                - If they prefer ESG, use ESG index funds (e.g. ESGV, ESGU, VSGX).
                - Use the "If the account fell 20%" answer as the truest risk signal.
                """);

        if (!notes.isEmpty()) {
            p.append("\nThe app already shows them these notes; keep your advice consistent and don't repeat them:\n");
            for (String n : notes) p.append("- ").append(n).append('\n');
        }

        p.append("""

                IMPORTANT FORMAT REQUIREMENT (the app parses this):
                Tickers are capital letters only (no dots). Allocations add up to 100 percent and to the monthly amount.
                For each holding, exactly:

                **[TICKER] - [PERCENTAGE]%%**
                - **Allocation:** $XXX.XX
                - **Reason:** Why this holding fits them (one or two sentences, beginner-friendly).

                For example:
                **VTI - 40%%**
                - **Allocation:** $264.80
                - **Reason:** Broad U.S. stock market exposure.

                Do not include full fund names or vary the bullet format. After the holdings, add one short paragraph
                starting "**Why this mix:**" that ties it to their answers.
                """);
        return p.toString();
    }

    private static void line(StringBuilder p, String label, String value) {
        if (value != null && !value.isBlank()) p.append("- ").append(label).append(": ").append(value).append('\n');
    }
}
