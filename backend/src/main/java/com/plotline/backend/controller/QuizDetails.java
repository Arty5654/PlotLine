package com.plotline.backend.controller;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * The budget quiz's housing, work/commute and insurance answers, turned into fixed budget lines
 * (your share of rent, utilities, internet, the commute) and notes for the AI.
 *
 *   housing:   {situation, totalRent, people, yourShare, mortgage, utilitiesIncluded, utilities, internet, internetInUtilities, rentersInsurance}
 *              (internetInUtilities: the quiz asks one "utilities & internet" amount; internet is then only sent
 *              when utilities come with the rent and internet is paid separately)
 *   work:      {arrangement: office|hybrid|remote|none, location, officeDays, mode, commuteMonthly, commuteSummary,
 *               commuteGas, commuteOther}  (newer apps: the commute split into gas and the rest, so there's
 *               no Commute line; it's at least that much in Gas and Transportation, which is how spending is tracked)
 *   insurance: {payFrequency, health, dental, vision}  (per paycheck, through work, so before taxes)
 *   household: {under5, age5to12, age13to17, adults, childcare}  (dependents by age; childcare only when typed, 0 = none)
 *   savings:   {emergencySaved, emergencyMonths, goals: [{name, target, saved, targetDate, monthlyNeeded}]}  (from the Plan tab)
 */
public record QuizDetails(Map<String, Object> housing, Map<String, Object> work, Map<String, Object> insurance,
                          Map<String, Object> costs, List<Map<String, Object>> subscriptions, Map<String, Object> bankAverages,
                          Map<String, Object> household, Map<String, Object> savings) {

    @SuppressWarnings("unchecked")
    public static QuizDetails from(Map<String, Object> quiz) {
        return new QuizDetails(
                quiz.get("housing") instanceof Map<?, ?> h ? (Map<String, Object>) h : Map.of(),
                quiz.get("work") instanceof Map<?, ?> w ? (Map<String, Object>) w : Map.of(),
                quiz.get("insurance") instanceof Map<?, ?> i ? (Map<String, Object>) i : Map.of(),
                quiz.get("otherCosts") instanceof Map<?, ?> c ? (Map<String, Object>) c : Map.of(),
                quiz.get("subscriptions") instanceof List<?> l ? (List<Map<String, Object>>) l : List.of(),
                quiz.get("bankAverages") instanceof Map<?, ?> b ? (Map<String, Object>) b : Map.of(),
                quiz.get("household") instanceof Map<?, ?> hh ? (Map<String, Object>) hh : Map.of(),
                quiz.get("savings") instanceof Map<?, ?> sv ? (Map<String, Object>) sv : Map.of());
    }

    // ── dependents ─────────────────────────────────────────────────────────

    int kidsUnder13() { return (int) (number(household.get("under5")) + number(household.get("age5to12"))); }

    /** "1 under 5, 2 aged 5–12" */
    String dependentAges() {
        List<String> parts = new ArrayList<>();
        int under5 = (int) number(household.get("under5")), young = (int) number(household.get("age5to12"));
        int teens = (int) number(household.get("age13to17")), adults = (int) number(household.get("adults"));
        if (under5 > 0) parts.add(under5 + " under 5");
        if (young > 0) parts.add(young + " aged 5-12");
        if (teens > 0) parts.add(teens + " aged 13-17");
        if (adults > 0) parts.add(adults + " adult" + (adults == 1 ? "" : "s") + " (18+)");
        return String.join(", ", parts);
    }

    /** subscriptions from the quiz (and the Subscriptions page), per month */
    public double subscriptionsMonthly() {
        return subscriptions.stream().mapToDouble(sub -> number(sub.get("cost"))).sum();
    }

    /** once-a-year (or a few-times-a-year) costs, as {name → per month} */
    @SuppressWarnings("unchecked")
    public Map<String, Double> yearlyMonthly() {
        Map<String, Double> out = new java.util.LinkedHashMap<>();
        if (costs.get("yearly") instanceof List<?> items) {
            for (Object o : items) {
                if (!(o instanceof Map<?, ?> m)) continue;
                Map<String, Object> item = (Map<String, Object>) m;
                String name = String.valueOf(item.getOrDefault("name", "")).strip();
                double amount = number(item.get("amount")) * Math.max(1, number(item.getOrDefault("timesPerYear", 1)));
                if (!name.isEmpty() && amount > 0) out.merge(name, Math.round(amount / 12.0 * 100) / 100.0, Double::sum);
            }
        }
        return out;
    }

    /** once-a-year costs with no amount: estimated ("Car maintenance" → "Car maintenance (2× a year)") */
    @SuppressWarnings("unchecked")
    public Map<String, Integer> yearlyToEstimate() {
        Map<String, Integer> out = new java.util.LinkedHashMap<>();
        if (costs.get("yearly") instanceof List<?> items) {
            for (Object o : items) {
                if (!(o instanceof Map<?, ?> m)) continue;
                Map<String, Object> item = (Map<String, Object>) m;
                String name = String.valueOf(item.getOrDefault("name", "")).strip();
                if (!name.isEmpty() && number(item.get("amount")) <= 0)
                    out.put(name, (int) Math.max(1, number(item.getOrDefault("timesPerYear", 1))));
            }
        }
        return out;
    }

    static double number(Object value) {
        if (value instanceof Number n) return n.doubleValue();
        if (value == null) return 0;
        try {
            return Double.parseDouble(String.valueOf(value).replace(",", "").replace("$", "").strip());
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    // ── insurance ──────────────────────────────────────────────────────────

    public double insurancePerPaycheck() {
        return number(insurance.get("health")) + number(insurance.get("dental")) + number(insurance.get("vision"));
    }

    /** health, dental and vision through work, per year (comes out before taxes) */
    public double insuranceYearly() {
        int periods = (int) number(insurance.getOrDefault("payFrequency", 26));
        if (!List.of(12, 24, 26, 52).contains(periods)) periods = 26;
        return insurancePerPaycheck() * periods;
    }

    // ── housing ────────────────────────────────────────────────────────────

    public String situation() { return String.valueOf(housing.getOrDefault("situation", "")); }

    /** your share: the share typed in, or the total split between the people living there */
    public double rentShare() {
        double share = number(housing.get("yourShare"));
        if (share > 0) return share;
        double total = number(housing.get("totalRent"));
        double people = Math.max(1, number(housing.get("people")));
        return total > 0 ? Math.round(total / people) : 0;
    }

    public boolean utilitiesIncluded() { return Boolean.TRUE.equals(housing.get("utilitiesIncluded")); }

    /** the quiz's Utilities amount covers internet too */
    public boolean internetInUtilities() { return Boolean.TRUE.equals(housing.get("internetInUtilities")); }

    // ── work ───────────────────────────────────────────────────────────────

    public String arrangement() { return String.valueOf(work.getOrDefault("arrangement", "")).toLowerCase(Locale.ROOT); }

    public double commuteMonthly() { return number(work.get("commuteMonthly")); }

    /** the commute is split into Gas and Transportation (no Commute line) */
    public boolean splitsCommute() { return work.containsKey("commuteGas") || work.containsKey("commuteOther"); }

    /**
     * The review screen's explanation for Gas and Transportation, written here (the AI's were vague):
     * what each covers, what driving and the commute come to, and what their transactions show.
     */
    public Map<String, String> drivingWhy() {
        Map<String, String> out = new java.util.LinkedHashMap<>();
        boolean commutes = arrangement().equals("office") || arrangement().equals("hybrid");
        double commuteGas = commutes ? number(work.get("commuteGas")) : 0, otherGas = number(costs.get("otherGas"));
        double commuteOther = commutes ? number(work.get("commuteOther")) : 0;
        double bankGas = number(bankAverages.get("Gas")), bankRides = number(bankAverages.get("Transportation"));

        StringBuilder gas = new StringBuilder("Fuel for all your driving");
        if (commuteGas > 0 || otherGas > 0) {
            List<String> parts = new ArrayList<>();
            if (commuteGas > 0) parts.add("$" + Math.round(commuteGas) + " to get to work");
            if (otherGas > 0) parts.add("$" + Math.round(otherGas) + " for other driving");
            gas.append(" (").append(String.join(" + ", parts)).append(")");
        }
        if (bankGas > 0) gas.append(". Your transactions show about $").append(Math.round(bankGas)).append(" a month");
        out.put("Gas", gas.append(".").toString());

        StringBuilder rides = new StringBuilder("Getting around besides gas: parking, tolls, Uber/Lyft, buses and trains");
        if (commuteOther > 0) rides.append(". Includes $").append(Math.round(commuteOther)).append(" a month for getting to work");
        if (bankRides > 0) rides.append(". Your transactions show about $").append(Math.round(bankRides)).append(" a month");
        out.put("Transportation", rides.append(".").toString());
        return out;
    }

    /**
     * Lines that have to be at least this much (the AI can add on top): Gas covers driving to work and
     * other driving, Transportation the commute's tolls, parking, transit or rides plus other travel.
     */
    public Map<String, Double> minimums() {
        Map<String, Double> out = new java.util.LinkedHashMap<>();
        if (!splitsCommute()) return out;
        boolean commutes = arrangement().equals("office") || arrangement().equals("hybrid");
        double gas = (commutes ? number(work.get("commuteGas")) : 0) + number(costs.get("otherGas"));
        double other = commutes ? number(work.get("commuteOther")) : 0;
        if (gas > 0) out.put("Gas", Math.round(gas * 100) / 100.0);
        if (other > 0) out.put("Transportation", Math.round(other * 100) / 100.0);
        return out;
    }

    /** fixed lines from these answers (they win over the same lines typed elsewhere) and categories to use */
    public void applyTo(List<String> categories, Map<String, Double> known) {
        String situation = situation();
        if (situation.equals("Renting") || situation.equals("Live with Others")) {
            double rent = rentShare();
            add(categories, "Rent");                     // blank: estimated
            if (rent > 0) known.put("Rent", rent);
        } else if (situation.equals("Own with Mortgage")) {
            double mortgage = number(housing.get("mortgage"));
            add(categories, "Mortgage");                 // blank: estimated (it used to be budgeted as Rent)
            categories.remove("Rent");
            known.remove("Rent");
            if (mortgage > 0) known.put("Mortgage", mortgage);
        } else if (situation.equals("Own Free and Clear")) {
            categories.remove("Rent");
        }
        if (utilitiesIncluded()) {
            categories.remove("Utilities");
            known.remove("Utilities");
        } else if (number(housing.get("utilities")) > 0) {
            known.put("Utilities", number(housing.get("utilities")));
            add(categories, "Utilities");
        }
        if (internetInUtilities() && !utilitiesIncluded()) { categories.remove("Internet"); known.remove("Internet"); }
        if (number(housing.get("internet")) > 0) { known.put("Internet", number(housing.get("internet"))); add(categories, "Internet"); }
        if (number(housing.get("rentersInsurance")) > 0) {
            known.put("Renters Insurance", number(housing.get("rentersInsurance")));
            add(categories, "Renters Insurance");
        }

        if (splitsCommute()) {
            categories.remove("Commute");
            known.remove("Commute");
            minimums().keySet().forEach(c -> add(categories, c));
        } else if (commuteMonthly() > 0) {
            known.put("Commute", commuteMonthly());
            add(categories, "Commute");
        }

        // other regular costs they know
        putIfSet(categories, known, "Phone", costs.get("phone"));
        putIfSet(categories, known, "Gym", costs.get("gym"));
        putIfSet(categories, known, "Medical", costs.get("medical"));
        putIfSet(categories, known, "Car Payment", costs.get("carPayment"));
        putIfSet(categories, known, "Car Insurance", costs.get("carInsurance"));
        if (!splitsCommute()) putIfSet(categories, known, "Gas", costs.get("otherGas")); // else part of the Gas minimum
        putIfSet(categories, known, "Pet Care", costs.get("petsMonthly"));
        if (number(costs.get("petsMonthly")) <= 0 && !pets().isEmpty()) add(categories, "Pet Care");
        yearlyMonthly().forEach((name, monthly) -> { known.put(name, monthly); add(categories, name); });
        yearlyToEstimate().keySet().forEach(name -> add(categories, name));
        if (subscriptionsMonthly() > 0) {
            known.put("Subscriptions", Math.round(subscriptionsMonthly() * 100) / 100.0);
            add(categories, "Subscriptions");
        }

        // childcare: what they pay, none (0), or estimated when there are kids under 13 and it was left blank
        if (household.containsKey("childcare")) {
            double childcare = number(household.get("childcare"));
            if (childcare > 0) { known.put("Childcare", childcare); add(categories, "Childcare"); }
            else { categories.remove("Childcare"); known.remove("Childcare"); }
        } else if (kidsUnder13() > 0) {
            add(categories, "Childcare");
        }

        // insurance through work is already out of the paycheck: no budget line for it
        if (insurancePerPaycheck() > 0) {
            // (Dental and Vision on their own are visits, paid either way)
            for (String c : List.of("Health Insurance", "Dental Insurance", "Vision Insurance")) { categories.remove(c); known.remove(c); }
        }
    }

    /** what they have saved and are saving for (from the Plan tab) */
    @SuppressWarnings("unchecked")
    String savingsNote() {
        if (savings.isEmpty()) return "";
        List<String> parts = new ArrayList<>();
        double emergency = number(savings.get("emergencySaved"));
        int months = (int) number(savings.getOrDefault("emergencyMonths", 3));
        parts.add("They have $" + Math.round(emergency) + " saved for emergencies; their goal is " + Math.max(1, months)
                + " months of expenses. If that's already reached, Savings can go toward their goals or investing; if not, building it comes first.");
        if (savings.get("goals") instanceof List<?> goals) {
            for (Object o : goals) {
                if (!(o instanceof Map<?, ?> m)) continue;
                Map<String, Object> g = (Map<String, Object>) m;
                String name = String.valueOf(g.getOrDefault("name", "")).strip();
                if (name.isEmpty()) continue;
                Object date = g.get("targetDate");
                double needed = number(g.get("monthlyNeeded"));
                parts.add("Goal \"" + name + "\": $" + Math.round(number(g.get("saved"))) + " of $" + Math.round(number(g.get("target"))) + " saved"
                        + (date != null ? ", by " + date : "") + (needed > 0 ? " (about $" + Math.round(needed) + "/month needed)" : "") + ".");
            }
        }
        parts.add("Keep one Savings line for all of it: PlotLine splits it between the emergency fund and their goals.");
        return String.join(" ", parts);
    }

    private static void putIfSet(List<String> categories, Map<String, Double> known, String category, Object value) {
        double amount = number(value);
        if (amount > 0) { known.put(category, amount); add(categories, category); }
    }

    /** "1 dog, 2 cats" */
    @SuppressWarnings("unchecked")
    String pets() {
        List<String> parts = new ArrayList<>();
        if (costs.get("pets") instanceof List<?> list) {
            for (Object o : list) {
                if (!(o instanceof Map<?, ?> m)) continue;
                int count = (int) number(((Map<String, Object>) m).get("count"));
                String type = String.valueOf(((Map<String, Object>) m).getOrDefault("type", "pet"));
                if (count > 0) parts.add(count + " " + type + (count == 1 ? "" : "s"));
            }
        }
        return String.join(", ", parts);
    }

    private static void add(List<String> categories, String category) {
        if (!categories.contains(category)) categories.add(category);
    }

    /** extra lines for the AI's instructions */
    public String promptNotes() {
        List<String> notes = new ArrayList<>();
        double people = number(housing.get("people"));
        if (people > 1) notes.add("They share their home with " + (int) (people - 1) + " other " + (people == 2 ? "person" : "people") + "; Rent is their share only.");
        String sit = situation();
        if ((sit.equals("Renting") || sit.equals("Live with Others")) && rentShare() <= 0)
            notes.add("Estimate Rent (their share" + (people > 1 ? ", split " + (int) people + " ways" : "") + ") at typical prices for their city.");
        if (sit.equals("Own with Mortgage") && number(housing.get("mortgage")) <= 0)
            notes.add("Estimate Mortgage (their monthly payment) at typical prices for their city.");
        if (utilitiesIncluded()) notes.add("Utilities are included in their rent.");
        else if (number(housing.get("utilities")) <= 0 && !sit.isEmpty())
            notes.add("Estimate Utilities for their share of the home" + (people > 1 ? " (split " + (int) people + " ways)" : "")
                    + (internetInUtilities() ? ", including internet" : "") + ".");
        else if (internetInUtilities()) notes.add("Utilities includes their internet.");
        switch (arrangement()) {
            case "remote" -> notes.add("They work from home: no commute.");
            case "none" -> notes.add("They don't commute to a job.");
            default -> {
                if (splitsCommute()) {
                    Object summary = work.get("commuteSummary");
                    double gas = number(work.get("commuteGas")), other = number(work.get("commuteOther"));
                    notes.add("Getting to work" + (summary != null ? " (" + summary + ")" : "") + " costs about $" + Math.round(gas + other)
                            + "/month: " + (gas > 0 ? "$" + Math.round(gas) + " of gas is part of Gas" : "")
                            + (gas > 0 && other > 0 ? ", and " : "")
                            + (other > 0 ? "$" + Math.round(other) + " (tolls, parking, transit or rides) is part of Transportation" : "")
                            + ". There's no separate Commute line.");
                } else if (commuteMonthly() > 0) {
                    Object summary = work.get("commuteSummary");
                    notes.add("Getting to work is its own line, Commute ($" + Math.round(commuteMonthly()) + "/month"
                            + (summary != null ? ": " + summary : "") + "). Transportation covers only other travel.");
                }
            }
        }
        if (insurancePerPaycheck() > 0) notes.add("Health, dental and vision insurance come out of their paycheck before taxes (already reflected in their take-home), so don't budget for them.");
        if (!pets().isEmpty() && number(costs.get("petsMonthly")) <= 0) notes.add("They have " + pets() + ": estimate Pet Care (food, vet, supplies).");
        int insuranceMonths = (int) number(costs.get("carInsuranceMonths"));
        if (insuranceMonths > 1 && number(costs.get("carInsurancePayment")) > 0)
            notes.add("They pay car insurance $" + Math.round(number(costs.get("carInsurancePayment"))) + (insuranceMonths == 12 ? " once a year" : " every " + insuranceMonths + " months")
                    + "; Car Insurance is the monthly amount set aside for it.");
        if (!yearlyMonthly().isEmpty()) notes.add("Yearly costs are set aside monthly as their own lines: " + String.join(", ", yearlyMonthly().keySet()) + ".");
        if (!yearlyToEstimate().isEmpty()) {
            List<String> parts = new ArrayList<>();
            yearlyToEstimate().forEach((name, times) -> parts.add(name + (times > 1 ? " (" + times + " times a year)" : "")));
            notes.add("Estimate a monthly set-aside (the yearly cost divided by 12) for these once-a-year costs: " + String.join(", ", parts) + ".");
        }
        if (!dependentAges().isEmpty()) {
            notes.add("Their dependents: " + dependentAges() + ". Budget for what they cost (food, clothes, school, activities"
                    + (number(household.get("under5")) > 0 ? ", diapers and baby supplies" : "") + ").");
        }
        if (kidsUnder13() > 0 && !household.containsKey("childcare")) notes.add("Estimate Childcare for their kids under 13 at local prices.");
        if (household.containsKey("childcare") && number(household.get("childcare")) <= 0) notes.add("They don't pay for childcare.");
        String savingsNote = savingsNote();
        if (!savingsNote.isEmpty()) notes.add(savingsNote);
        String mode = String.valueOf(work.getOrDefault("mode", ""));
        if (!splitsCommute() && number(bankAverages.get("Gas")) > 0 && commuteMonthly() > 0 && (mode.equals("drive") || mode.equals("carpool-driver")))
            notes.add("Their bank's Gas already includes driving to work, which is its own Commute line: set Gas to only the rest, don't count commute gas twice.");
        if (!minimums().isEmpty()) {
            List<String> parts = new ArrayList<>();
            minimums().forEach((c, v) -> parts.add(c + " at least $" + Math.round(v)));
            notes.add("Minimums from their driving and commute: " + String.join(", ", parts)
                    + ". Gas is all their driving (to work and otherwise); Transportation is everything else for getting around.");
        }
        if (!bankAverages.isEmpty()) {
            List<String> spent = new ArrayList<>();
            bankAverages.forEach((category, amount) -> { if (number(amount) > 0) spent.add(category + " $" + Math.round(number(amount))); });
            if (!spent.isEmpty()) notes.add("What they actually spend per month (from their linked bank or card transactions): " + String.join(", ", spent)
                    + ". Start each category from what they really spend; you may trim flexible ones (eating out, shopping, entertainment) to fit their goals and income, but don't set them unrealistically low.");
        }
        return notes.isEmpty() ? "" : "More about them:\n- " + String.join("\n- ", notes);
    }
}
