package com.plotline.backend.controller;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** The quiz's housing, commute and insurance answers become budget lines. */
class QuizDetailsTest {

    @Test
    @DisplayName("Rent split with roommates, utilities included, commute line, insurance out of the paycheck")
    void lines() {
        var details = QuizDetails.from(Map.of(
                "housing", Map.of("situation", "Renting", "totalRent", 2400, "people", 3, "utilitiesIncluded", true, "internet", 25),
                "work", Map.of("arrangement", "hybrid", "commuteMonthly", 186, "commuteSummary", "drive 28 mi round trip, 3 days/week"),
                "insurance", Map.of("payFrequency", 26, "health", 60, "dental", 8, "vision", 2)));
        List<String> categories = new ArrayList<>(List.of("Rent", "Groceries", "Utilities", "Health Insurance", "Transportation"));
        Map<String, Double> known = new LinkedHashMap<>(Map.of("Utilities", 120.0));
        details.applyTo(categories, known);

        assertThat(known).containsEntry("Rent", 800.0).containsEntry("Internet", 25.0).containsEntry("Commute", 186.0)
                .doesNotContainKey("Utilities");
        assertThat(categories).contains("Rent", "Commute", "Internet").doesNotContain("Utilities", "Health Insurance");
        assertThat(details.insuranceYearly()).isEqualTo(70 * 26);
        assertThat(details.promptNotes()).contains("2 other people").contains("included in their rent")
                .contains("Commute ($186/month: drive 28 mi").contains("before taxes");
    }

    @Test
    @DisplayName("A share typed in wins; remote workers get no commute; a mortgage replaces rent")
    void variants() {
        var renter = QuizDetails.from(Map.of("housing", Map.of("situation", "Live with Others", "yourShare", 650, "totalRent", 3000, "people", 2)));
        assertThat(renter.rentShare()).isEqualTo(650);

        var owner = QuizDetails.from(Map.of("housing", Map.of("situation", "Own with Mortgage", "mortgage", 1900),
                "work", Map.of("arrangement", "remote")));
        List<String> categories = new ArrayList<>(List.of("Rent", "Groceries"));
        Map<String, Double> known = new LinkedHashMap<>();
        owner.applyTo(categories, known);
        assertThat(known).containsEntry("Mortgage", 1900.0).doesNotContainKey("Commute");
        assertThat(categories).contains("Mortgage").doesNotContain("Rent");
        assertThat(owner.promptNotes()).contains("work from home");
    }

    @Test
    @DisplayName("Subscriptions, yearly costs, pets, phone/gym/medical, car costs and bank spending")
    void otherCosts() {
        var details = QuizDetails.from(Map.of(
                "subscriptions", List.of(Map.of("name", "Spotify", "cost", 11.99), Map.of("name", "Netflix", "cost", "15.49")),
                "otherCosts", Map.of("phone", 45, "gym", 30, "carPayment", 310, "otherGas", 60,
                        "pets", List.of(Map.of("type", "dog", "count", 1)),
                        "yearly", List.of(Map.of("name", "Trips", "amount", 800, "timesPerYear", 2),
                                          Map.of("name", "Car registration", "amount", 120))),
                "bankAverages", Map.of("Eating Out", 410, "Groceries", 380)));
        List<String> categories = new ArrayList<>(List.of("Groceries"));
        Map<String, Double> known = new LinkedHashMap<>();
        details.applyTo(categories, known);
        assertThat(known).containsEntry("Subscriptions", 27.48).containsEntry("Phone", 45.0).containsEntry("Gym", 30.0)
                .containsEntry("Car Payment", 310.0).containsEntry("Gas", 60.0)
                .containsEntry("Trips", 133.33).containsEntry("Car registration", 10.0)
                .doesNotContainKey("Eating Out");                 // bank amounts are a starting point, not fixed
        assertThat(categories).contains("Pet Care", "Trips", "Car registration");
        assertThat(details.promptNotes()).contains("1 dog").contains("Eating Out $410").contains("Start each category from what they really spend");
    }

    @Test
    @DisplayName("Blank rent or mortgage is estimated (a blank mortgage isn't budgeted as Rent); internet counts as a utility")
    void blanksAndInternet() {
        var renter = QuizDetails.from(Map.of("housing", Map.of("situation", "Renting", "totalRent", 0, "people", 2,
                "utilitiesIncluded", false, "internetInUtilities", true)));
        List<String> categories = new ArrayList<>(List.of("Groceries", "Internet"));
        Map<String, Double> known = new LinkedHashMap<>(Map.of("Internet", 70.0));
        renter.applyTo(categories, known);
        assertThat(categories).contains("Rent").doesNotContain("Internet");
        assertThat(known).doesNotContainKey("Rent").doesNotContainKey("Internet");
        assertThat(renter.promptNotes()).contains("Estimate Rent (their share, split 2 ways)").contains("including internet");

        var owner = QuizDetails.from(Map.of("housing", Map.of("situation", "Own with Mortgage")));
        categories = new ArrayList<>(List.of("Rent", "Groceries"));
        owner.applyTo(categories, new LinkedHashMap<>());
        assertThat(categories).contains("Mortgage").doesNotContain("Rent");
        assertThat(owner.promptNotes()).contains("Estimate Mortgage");

        // utilities come with the rent, internet paid separately: its own line
        var included = QuizDetails.from(Map.of("housing", Map.of("situation", "Renting", "yourShare", 900,
                "utilitiesIncluded", true, "internet", 55, "internetInUtilities", false)));
        categories = new ArrayList<>(List.of("Utilities"));
        known = new LinkedHashMap<>();
        included.applyTo(categories, known);
        assertThat(known).containsEntry("Internet", 55.0).containsEntry("Rent", 900.0);
        assertThat(categories).contains("Internet").doesNotContain("Utilities");
    }

    @Test
    @DisplayName("The commute is split into Gas and Transportation minimums (no Commute line); blank yearly costs are estimated")
    void commuteSplitAndYearlyEstimates() {
        var details = QuizDetails.from(Map.of(
                "work", Map.of("arrangement", "office", "mode", "drive", "commuteMonthly", 327, "commuteGas", 141, "commuteOther", 186,
                        "commuteSummary", "drive 65 mi round trip, 5 days/week, tolls"),
                "otherCosts", Map.of("otherGas", 18.2, "yearly", List.of(Map.of("name", "Car maintenance", "timesPerYear", 2),
                        Map.of("name", "Car registration", "amount", 95)))));
        List<String> categories = new ArrayList<>(List.of("Groceries", "Commute"));
        Map<String, Double> known = new LinkedHashMap<>();
        details.applyTo(categories, known);
        assertThat(details.minimums()).containsEntry("Gas", 159.2).containsEntry("Transportation", 186.0);
        assertThat(categories).contains("Gas", "Transportation", "Car maintenance", "Car registration").doesNotContain("Commute");
        assertThat(known).doesNotContainKeys("Commute", "Gas", "Car maintenance").containsEntry("Car registration", 7.92);
        assertThat(details.promptNotes()).contains("$141 of gas is part of Gas").contains("$186 (tolls, parking, transit or rides) is part of Transportation")
                .contains("Gas at least $159").contains("Car maintenance (2 times a year)").doesNotContain("Commute line:");

        // no commute: Gas is all driving, Transportation the rest, with what their transactions show
        var noCommute = QuizDetails.from(Map.of("work", Map.of("arrangement", "remote", "commuteGas", 0, "commuteOther", 0),
                "bankAverages", Map.of("Gas", 104, "Transportation", 132)));
        assertThat(noCommute.drivingWhy()).containsEntry("Gas", "Fuel for all your driving. Your transactions show about $104 a month.")
                .containsEntry("Transportation", "Getting around besides gas: parking, tolls, Uber/Lyft, buses and trains. Your transactions show about $132 a month.");

        // working from home: no commute in the minimums
        var remote = QuizDetails.from(Map.of("work", Map.of("arrangement", "remote", "commuteGas", 141, "commuteOther", 0),
                "otherCosts", Map.of("otherGas", 30)));
        assertThat(remote.minimums()).containsOnlyKeys("Gas").containsEntry("Gas", 30.0);
    }

    @Test
    @DisplayName("Dependents by age: childcare typed, none (0), or estimated for kids under 13")
    void dependents() {
        var typed = QuizDetails.from(Map.of("household", Map.of("under5", 1, "age5to12", 1, "childcare", 1100)));
        List<String> categories = new ArrayList<>(List.of("Groceries"));
        Map<String, Double> known = new LinkedHashMap<>();
        typed.applyTo(categories, known);
        assertThat(known).containsEntry("Childcare", 1100.0);
        assertThat(typed.promptNotes()).contains("1 under 5, 1 aged 5-12").contains("diapers");

        var none = QuizDetails.from(Map.of("household", Map.of("age5to12", 2, "childcare", 0)));
        categories = new ArrayList<>(List.of("Groceries", "Childcare"));
        known = new LinkedHashMap<>();
        none.applyTo(categories, known);
        assertThat(categories).doesNotContain("Childcare");
        assertThat(none.promptNotes()).contains("don't pay for childcare");

        var estimate = QuizDetails.from(Map.of("household", Map.of("under5", 1)));
        categories = new ArrayList<>(List.of("Groceries"));
        estimate.applyTo(categories, new LinkedHashMap<>());
        assertThat(categories).contains("Childcare");
        assertThat(estimate.promptNotes()).contains("Estimate Childcare");

        var teens = QuizDetails.from(Map.of("household", Map.of("age13to17", 1, "adults", 1)));
        categories = new ArrayList<>(List.of("Groceries"));
        teens.applyTo(categories, new LinkedHashMap<>());
        assertThat(categories).doesNotContain("Childcare");
        assertThat(teens.promptNotes()).contains("1 aged 13-17, 1 adult (18+)");
    }

    @Test
    @DisplayName("Savings from the Plan tab and commute gas the bank already counts")
    void savingsAndGas() {
        var details = QuizDetails.from(Map.of(
                "savings", Map.of("emergencySaved", 6000, "emergencyMonths", 3,
                        "goals", List.of(Map.of("name", "Car", "target", 5000, "saved", 1200, "targetDate", "2027-06-01", "monthlyNeeded", 190))),
                "work", Map.of("arrangement", "office", "mode", "drive", "commuteMonthly", 120),
                "bankAverages", Map.of("Gas", 160)));
        String notes = details.promptNotes();
        assertThat(notes).contains("$6000 saved for emergencies").contains("3 months")
                .contains("Goal \"Car\": $1200 of $5000 saved, by 2027-06-01 (about $190/month needed)")
                .contains("Keep one Savings line")
                .contains("don't count commute gas twice");
        assertThat(QuizDetails.from(Map.of()).promptNotes()).doesNotContain("emergencies");
        assertThat(QuizDetails.from(Map.of("otherCosts", Map.of("carInsurance", 100, "carInsurancePayment", 600, "carInsuranceMonths", 6)))
                .promptNotes()).contains("car insurance $600 every 6 months");
    }

    @Test
    @DisplayName("Budgeting styles: how much of take-home to plan, and the rule the AI follows")
    void styles() {
        assertThat(BudgetingStyle.from(Map.of("budgetingStyle", "fiftyThirtyTwenty")).rules(4000)).contains("$2000").contains("$1200").contains("$800");
        var payFirst = BudgetingStyle.from(Map.of("budgetingStyle", "payYourselfFirst", "savePercent", 15));
        assertThat(payFirst.rules(4000)).contains("at least 15% of take-home ($600)");
        assertThat(BudgetingStyle.from(Map.of("budgetingStyle", "flexible")).share("High")).isEqualTo(0.88);
        assertThat(BudgetingStyle.from(Map.of("budgetingStyle", "everyDollar")).assignsEverything()).isTrue();
        assertThat(BudgetingStyle.from(Map.of("spendingStyle", "Low")).share("Low")).isEqualTo(0.75); // older quizzes
    }
}
