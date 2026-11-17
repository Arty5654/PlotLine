package com.plotline.backend.retune;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** Re-tuning never raises a category without paying for it. */
class RetuneAdvisorTest {

    private static Map<String, Double> map(Object... pairs) {
        Map<String, Double> m = new LinkedHashMap<>();
        for (int i = 0; i < pairs.length; i += 2) m.put((String) pairs[i], ((Number) pairs[i + 1]).doubleValue());
        return m;
    }

    @Test
    @DisplayName("Over on groceries, under on eating out: move the money (plus unassigned money for the rest)")
    void rebalance() {
        var budget = map("Groceries", 250, "Eating Out", 200, "Rent", 1200, "Savings", 300);
        var actual = map("Groceries", 340, "Eating Out", 120, "Rent", 1200);
        var advice = RetuneAdvisor.advise(budget, actual, 3000);
        var s = advice.suggestions().get(0);
        assertThat(s.kind()).isEqualTo("rebalance");
        assertThat(s.changes()).containsEntry("Groceries", 340.0).containsEntry("Eating Out", 120.0);
        assertThat(s.message()).contains("Eating Out ($120 of $200)").contains("doesn't assign yet");
        assertThat(advice.warnings()).isEmpty();
    }

    @Test
    @DisplayName("Only partly covered: raise what's covered and suggest slowing down the rest; Savings is only an option")
    void partial() {
        var budget = map("Groceries", 250, "Eating Out", 200, "Rent", 1250, "Savings", 300);  // all $2,000 assigned
        var actual = map("Groceries", 340, "Eating Out", 120, "Rent", 1250);
        var s = RetuneAdvisor.advise(budget, actual, 2000).suggestions().get(0);
        assertThat(s.kind()).isEqualTo("partial");
        assertThat(s.changes()).containsEntry("Groceries", 330.0).containsEntry("Eating Out", 120.0);
        assertThat(s.message()).contains("$10 less a month on Groceries");
        assertThat(s.alternative().changes()).containsEntry("Groceries", 340.0).containsEntry("Savings", 210.0);
    }

    @Test
    @DisplayName("Nothing has room: advice to slow down, no automatic raise")
    void slowDown() {
        var budget = map("Groceries", 250, "Rent", 1450, "Savings", 50);
        var actual = map("Groceries", 340, "Rent", 1450);
        var s = RetuneAdvisor.advise(budget, actual, 1750).suggestions().get(0);
        assertThat(s.kind()).isEqualTo("slowDown");
        assertThat(s.changes()).isEmpty();
        assertThat(s.message()).contains("spend about $90 less a month on Groceries");
        assertThat(s.alternative()).isNull(); // Savings ($50) can't cover $90
    }

    @Test
    @DisplayName("Rent never gives its money away; spending well under budget is offered to Savings (keeping at least half)")
    void fixedAndLower() {
        var budget = map("Rent", 1500, "Entertainment", 200, "Savings", 300);
        var actual = map("Rent", 1200, "Entertainment", 50);
        var advice = RetuneAdvisor.advise(budget, actual, 2000);
        assertThat(advice.suggestions()).hasSize(1);
        var s = advice.suggestions().get(0);
        assertThat(s.kind()).isEqualTo("lower");
        assertThat(s.changes()).containsEntry("Entertainment", 100.0).containsEntry("Savings", 400.0);
    }

    @Test
    @DisplayName("Spending that comes in bursts (Home, Travel, once-a-year costs) is never lowered or used to pay for another")
    void bursty() {
        var budget = map("Home", 45, "Travel", 200, "Car registration", 10, "Groceries", 300, "Savings", 300);
        var advice = RetuneAdvisor.advise(budget, List.of(map("Groceries", 290), map("Groceries", 295)), 3000, Set.of("Car registration"));
        assertThat(advice.suggestions()).isEmpty();                  // not "Home $45 → $1"
    }

    @Test
    @DisplayName("A change has to hold in every month: one big month isn't a pattern")
    void consistent() {
        var budget = map("Eating Out", 200, "Entertainment", 300, "Savings", 300);
        // eating out over in one month only: no raise
        var once = RetuneAdvisor.advise(budget, List.of(map("Eating Out", 400, "Entertainment", 100), map("Eating Out", 150, "Entertainment", 100)),
                3000, Set.of());
        assertThat(once.suggestions()).noneMatch(x -> x.category().equals("Eating Out"));
        // over in both: a raise, paid for by entertainment (never below its busiest month)
        var both = RetuneAdvisor.advise(budget, List.of(map("Eating Out", 260, "Entertainment", 100), map("Eating Out", 280, "Entertainment", 140)),
                3000, Set.of());
        var raise = both.suggestions().stream().filter(x -> x.category().equals("Eating Out")).findFirst().orElseThrow();
        assertThat(raise.changes().get("Entertainment")).isGreaterThanOrEqualTo(150.0);
    }

    @Test
    @DisplayName("Spending more than take-home is called out first")
    void overspending() {
        var advice = RetuneAdvisor.advise(map("Rent", 1500, "Groceries", 300), map("Rent", 1500, "Groceries", 700), 2000);
        assertThat(advice.warnings().get(0)).contains("$200 a month more than you bring home");
    }
}
