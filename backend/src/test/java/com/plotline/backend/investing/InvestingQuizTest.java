package com.plotline.backend.investing;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.plotline.backend.dto.SavedPortfolio.AccountType;
import com.plotline.backend.investing.InvestorFacts.Debt;
import com.plotline.backend.investing.InvestorFacts.Facts;
import com.plotline.backend.investing.InvestorFacts.Ira;

/** The Roth IRA and Brokerage quizzes: notes worked out from the numbers, and a prompt per account. */
class InvestingQuizTest {

    private static final Ira IRA = new Ira(2026, 7500, 50, 1100, List.of(153000.0, 168000.0), List.of(242000.0, 252000.0));
    private static final LocalDate JULY = LocalDate.of(2026, 7, 10);

    private Facts facts(Double income, double monthly, double saved, double target, List<Debt> debts) {
        return new Facts(income, 0, monthly, income == null ? null : 22, saved, target, 3, debts, List.of(), 0, Map.of(), IRA);
    }

    @Test
    @DisplayName("Roth IRA: the budget would go over this year's limit; a full year says so")
    void rothLimit() {
        // July to December is 6 months: 6 × $1,000 = $6,000, but only $7,500 − $3,000 = $4,500 of room
        List<String> notes = InvestingQuiz.notes(AccountType.ROTH_IRA,
                Map.of("age", "30", "contributedThisYear", "3000"), facts(null, 1000, -1, 0, List.of()), JULY);
        assertThat(notes).hasSize(1);
        assertThat(notes.get(0)).contains("$6,000 by December").contains("$4,500 more in 2026").contains("After about 4 months");

        List<String> full = InvestingQuiz.notes(AccountType.ROTH_IRA,
                Map.of("age", "30", "contributedThisYear", "7500"), facts(null, 500, -1, 0, List.of()), JULY);
        assertThat(full.get(0)).contains("full $7,500");

        // 50 and older: $1,100 more room
        assertThat(InvestingQuiz.rothRoom(Map.of("age", "55"), facts(null, 0, -1, 0, List.of()))).isEqualTo(8600);
    }

    @Test
    @DisplayName("Roth IRA: income over the limit, or in the range where it shrinks (married uses the joint range)")
    void rothIncome() {
        assertThat(InvestingQuiz.notes(AccountType.ROTH_IRA, Map.of("filingStatus", "Single"),
                facts(175000.0, 0, -1, 0, List.of()), JULY)).anyMatch(n -> n.contains("over the Roth IRA limit") && n.contains("backdoor"));
        assertThat(InvestingQuiz.notes(AccountType.ROTH_IRA, Map.of("filingStatus", "Single"),
                facts(160000.0, 0, -1, 0, List.of()), JULY)).anyMatch(n -> n.contains("limit shrinks"));
        assertThat(InvestingQuiz.notes(AccountType.ROTH_IRA, Map.of("filingStatus", "Married filing jointly"),
                facts(175000.0, 0, -1, 0, List.of()), JULY)).isEmpty();
    }

    @Test
    @DisplayName("Both: an emergency fund that isn't full and a high-interest card come first; a partial 401(k) match too")
    void planFirst() {
        Facts f = facts(60000.0, 200, 1000, 6000, List.of(new Debt("Visa", 24.99, 1800)));
        List<String> roth = InvestingQuiz.notes(AccountType.ROTH_IRA, Map.of("workplacePlan", "Partial match"), f, JULY);
        assertThat(roth).anyMatch(n -> n.contains("full 401(k) match"));
        assertThat(roth).anyMatch(n -> n.contains("$1,000 of its $6,000"));
        assertThat(roth).anyMatch(n -> n.contains("Visa charges 24.99% interest"));

        // the app's linked balance wins over the Plan's typed one
        assertThat(InvestingQuiz.notes(AccountType.BROKERAGE, Map.of("emergencySaved", "7000"),
                facts(null, 200, 1000, 6000, List.of()), JULY)).isEmpty();
    }

    @Test
    @DisplayName("Brokerage: money needed soon stays safe; retirement money points to a Roth IRA first")
    void brokerageNotes() {
        List<String> notes = InvestingQuiz.notes(AccountType.BROKERAGE,
                Map.of("horizon", "Under 3 years", "purpose", "Extra retirement"), facts(null, 300, -1, 0, List.of()), JULY);
        assertThat(notes).anyMatch(n -> n.contains("within 3 years"));
        assertThat(notes).anyMatch(n -> n.contains("Roth IRA usually beats Brokerage"));
    }

    @Test
    @DisplayName("Each account gets its own prompt, with the answers, the estimated bracket and the other account's holdings")
    void prompts() {
        Facts f = new Facts(85000.0, 0, 400, 22, -1, 0, 3, List.of(), List.of("VTI", "BND"), 0, Map.of(), IRA);
        Map<String, String> brokerage = Map.of("age", "26", "dropReaction", "Wait it out", "style", "A few index funds",
                "purpose", "A home", "horizon", "3-5 years", "taxBracket", "Not sure");
        String p = InvestingQuiz.prompt(AccountType.BROKERAGE, brokerage, f, List.of("Fill your emergency fund."), JULY);
        assertThat(p).contains("taxable brokerage account").contains("A home").contains("22% (estimated from their salary)")
                .contains("Roth IRA already holds: VTI, BND").contains("Fill your emergency fund.").contains("**[TICKER] - [PERCENTAGE]%%**")
                .contains("Risk tolerance: Medium").doesNotContain("Target Retirement");

        String roth = InvestingQuiz.prompt(AccountType.ROTH_IRA, Map.of("age", "26", "retireAge", "65", "style", "One fund"), f, List.of(), JULY);
        // 26 in 2026, retiring at 65: 2065
        assertThat(roth).contains("Roth IRA").contains("about 39 years, around 2065").contains("VLXVX (Vanguard Target Retirement 2065), at 100%")
                .doesNotContain("municipal");
        // 30 retiring at 65 in 2026 → 2061 → the 2060 fund; no age → none
        assertThat(InvestingQuiz.targetDateFund(Map.of("age", "30", "retireAge", "65"), JULY).getValue()).isEqualTo("VTTSX");
        assertThat(InvestingQuiz.targetDateFund(Map.of(), JULY)).isNull();
        assertThat(InvestingQuiz.prompt(AccountType.ROTH_IRA, Map.of("age", "26", "style", "A few index funds"), f, List.of(), JULY))
                .doesNotContain("Target Retirement");

        assertThat(InvestingQuiz.riskTolerance(Map.of("dropReaction", "Sell to stop the loss"))).isEqualTo("Low");
        assertThat(InvestingQuiz.riskTolerance(Map.of("dropReaction", "Buy more while it's cheaper"))).isEqualTo("High");
        assertThat(InvestingQuiz.riskTolerance(Map.of("riskTolerance", "High"))).isEqualTo("High"); // an older app
    }

    @Test
    @DisplayName("Tickers are read from both portfolio formats")
    void tickers() {
        assertThat(InvestorFacts.tickers("**VTI - 60%%**\n- **Allocation:** $300\n**BRK.B** - 20% - $40")).containsExactly("VTI", "BRK.B");
    }
}
