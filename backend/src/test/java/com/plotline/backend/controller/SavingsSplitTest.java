package com.plotline.backend.controller;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** The quiz budget's Savings split between the emergency fund and the Plan tab's goals. */
class SavingsSplitTest {

    /** $2,000 of spending a month, and Savings */
    private Map<String, Double> budget(double savings) {
        Map<String, Double> b = new LinkedHashMap<>();
        b.put("Rent", 1200.0);
        b.put("Groceries", 500.0);
        b.put("Debt - Visa", 300.0);
        b.put("Savings", savings);
        return b;
    }

    private Map<String, Object> savings(double emergencySaved, List<Map<String, Object>> goals) {
        return Map.of("emergencySaved", emergencySaved, "emergencyMonths", 3, "goals", goals);
    }

    private Map<String, Object> goal(String name, double target, double saved, String date, double needed) {
        Map<String, Object> g = new HashMap<>(Map.of("name", name, "target", target, "saved", saved, "monthlyNeeded", needed));
        if (date != null) g.put("targetDate", date);
        return g;
    }

    @Test
    @DisplayName("Fund not full: dated goals get their need from up to half, the fund the rest; nothing is lost")
    void shared() {
        Map<String, Double> b = budget(600);
        Map<String, String> why = new HashMap<>();
        SavingsSplit.apply(b, why, savings(1000, List.of(goal("Trip", 3000, 600, "2027-06-01", 200),
                goal("Car", 8000, 0, "2028-01-01", 400))), Set.of());
        assertThat(b.get("Savings - Trip")).isEqualTo(200.0);      // nearest date first: its whole need
        assertThat(b.get("Savings - Car")).isEqualTo(100.0);       // the rest of the half
        assertThat(b.get("Emergency Fund")).isEqualTo(300.0);      // the other half (needs $5,000 more)
        assertThat(b).doesNotContainKey("Savings");
        assertThat(b.values().stream().mapToDouble(Double::doubleValue).sum()).isEqualTo(2000 + 600);
        assertThat(why.get("Emergency Fund")).contains("$1,000 of $6,000").contains("3 months");
        assertThat(why.get("Savings - Trip")).contains("$200 a month reaches $3,000 by Jun 2027");
        assertThat(why.get("Savings - Car")).contains("$100 of the $400");
    }

    @Test
    @DisplayName("Fund full: goals get all they need; the rest stays in Savings; reached and undated goals get nothing")
    void fundFull() {
        Map<String, Double> b = budget(500);
        SavingsSplit.apply(b, new HashMap<>(), savings(9000, List.of(goal("Trip", 3000, 600, "2027-06-01", 200),
                goal("Done", 500, 500, "2027-01-01", 0), goal("Someday", 10000, 0, null, 0))), Set.of());
        assertThat(b.get("Savings - Trip")).isEqualTo(200.0);
        assertThat(b.get("Savings")).isEqualTo(300.0);
        assertThat(b).doesNotContainKeys("Emergency Fund", "Savings - Done", "Savings - Someday");
    }

    @Test
    @DisplayName("Almost full: the fund gets only what it still needs, and short goals get the rest")
    void topsUp() {
        Map<String, Double> b = budget(1000);
        SavingsSplit.apply(b, new HashMap<>(), savings(5900, List.of(goal("Car", 8000, 0, "2027-06-01", 800))), Set.of());
        // half ($500) to the car first, then the fund's last $100, then the car's other $300
        assertThat(b.get("Emergency Fund")).isEqualTo(100.0);
        assertThat(b.get("Savings - Car")).isEqualTo(800.0);
        assertThat(b.get("Savings")).isEqualTo(100.0);
    }

    @Test
    @DisplayName("A goal without a date keeps what the budget gives it now (set in Plan)")
    void keepsUndated() {
        Map<String, Double> b = budget(500);
        Map<String, String> why = new HashMap<>();
        SavingsSplit.apply(b, why, savings(9000, List.of(goal("MacBook", 1200, 0, null, 0))), Set.of(),
                Map.of("Savings - MacBook", 50.0, "Rent", 1200.0));
        assertThat(b.get("Savings - MacBook")).isEqualTo(50.0);
        assertThat(b.get("Savings")).isEqualTo(450.0);
        assertThat(why.get("Savings - MacBook")).contains("as you set it in your Plan");
    }

    @Test
    @DisplayName("Amounts typed on the review screen stay; nothing from the Plan tab: unchanged")
    void lockedAndEmpty() {
        Map<String, Double> b = budget(600);
        b.put("Savings - Trip", 50.0);
        SavingsSplit.apply(b, new HashMap<>(), savings(9000, List.of(goal("Trip", 3000, 600, "2027-06-01", 200))),
                Set.of("Savings - Trip"));
        assertThat(b.get("Savings - Trip")).isEqualTo(50.0);
        assertThat(b.get("Savings")).isEqualTo(600.0);

        Map<String, Double> untouched = budget(600);
        SavingsSplit.apply(untouched, new HashMap<>(), Map.of(), Set.of());
        assertThat(untouched).isEqualTo(budget(600));
    }
}
