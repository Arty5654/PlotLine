package com.plotline.backend.afford;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.plotline.backend.afford.AffordCheck.Context;
import com.plotline.backend.afford.AffordCheck.Cut;
import com.plotline.backend.afford.AffordCheck.Goal;
import com.plotline.backend.afford.AffordCheck.Purchase;
import com.plotline.backend.afford.AffordCheck.Result;
import com.plotline.backend.afford.AffordCheck.Subscription;

/** "Can I afford it?": the answer from the budget and Plan, and the short-term cut plan. */
class AffordCheckTest {

    private static final LocalDate TODAY = LocalDate.of(2026, 11, 10);

    /** $3,000 take-home; the budget assigns $2,900: $100 unassigned + $200 Savings = $300 a month */
    private Map<String, Double> budget() {
        Map<String, Double> b = new LinkedHashMap<>();
        b.put("Rent", 1200.0);
        b.put("Groceries", 400.0);
        b.put("Eating Out", 300.0);
        b.put("Entertainment", 100.0);
        b.put("Subscriptions", 30.0);
        b.put("Debt - Visa", 40.0);
        b.put("Extra Debt Payment", 60.0);
        b.put("Savings - Trip", 100.0);
        b.put("Roth IRA", 470.0);
        b.put("Savings", 200.0);
        return b;
    }

    private Context context(Map<String, Double> budget, Map<String, Double> spent, List<Goal> goals, double emergency) {
        return new Context(budget, spent, Set.of("rent", "subscriptions", "roth ira", "savings"), 3000, goals, emergency, 6000,
                24, "Visa", List.of(new Subscription("Spotify", 12), new Subscription("Netflix", 18)), TODAY);
    }

    private Context context() { return context(budget(), Map.of("Eating Out", 100.0), List.of(), 0); }

    private Purchase buy(double price) { return new Purchase("Headphones", price, null, "cash", 0, false); }

    @Test
    @DisplayName("Fits: unassigned take-home, then this month's Savings")
    void fits() {
        Result r = AffordCheck.check(buy(250), context());
        assertThat(r.verdict()).isEqualTo("fits");
        assertThat(r.sources()).extracting(AffordCheck.Source::amount).containsExactly(100.0, 150.0);
        assertThat(r.cutPlan()).isNull();
        // $3,000 a month is about $17.31 an hour: $250 is about 14.4 hours
        assertThat(r.hoursOfWork()).isEqualTo(14.4);
    }

    @Test
    @DisplayName("Fits if you skip what's left of this month's wants (Eating Out has $200 left, Entertainment $100)")
    void fitsIfYouSkip() {
        Result r = AffordCheck.check(buy(450), context());
        assertThat(r.verdict()).isEqualTo("fitsIfYouSkip");
        assertThat(r.detail()).contains("$150 comes from not spending the rest of this month's Eating Out");
        // groceries, rent and subscriptions are never "skipped"
        assertThat(r.sources()).noneMatch(s -> s.label().contains("Groceries") || s.label().contains("Rent"));
    }

    @Test
    @DisplayName("By a date: what's set aside each month gets there; too soon gets a cut plan instead")
    void byDate() {
        // Nov 10 → Mar 15: 4 months at $300 = $1,200
        Purchase inFourMonths = new Purchase("Laptop", 1200, LocalDate.of(2027, 3, 15), "cash", 0, false);
        Result r = AffordCheck.check(inFourMonths, context());
        assertThat(r.verdict()).isEqualTo("fitsByDate");
        assertThat(r.headline()).isEqualTo("Yes, by March 2027");
        assertThat(r.sources().get(0).label()).isEqualTo("Set aside $300 a month until March 2027");
        assertThat(r.cutPlan().cuts()).noneMatch(Cut::suggested);   // nothing needs cutting; they're there to pick

        Purchase nextMonth = new Purchase("Laptop", 1200, LocalDate.of(2026, 12, 20), "cash", 0, false);
        Result soon = AffordCheck.check(nextMonth, context());
        assertThat(soon.verdict()).isEqualTo("notYet");
        // one month: $1,200 needs $900 more than the $300 set aside
        assertThat(soon.cutPlan().monthlyNeeded()).isEqualTo(900);
        assertThat(soon.cutPlan().cuts()).extracting(Cut::kind).startsWith("trim", "trim");
        // $105 + $35 + $18 + $12 + $100 + $60 = $330: all suggested, still short, so it's ready later
        assertThat(soon.cutPlan().cuts()).allMatch(Cut::suggested);

        // a small gap: only the first trim is suggested, the rest are there to pick
        Result small = AffordCheck.check(new Purchase("Desk", 400, LocalDate.of(2026, 12, 20), "cash", 0, false), context());
        assertThat(small.cutPlan().monthlyNeeded()).isEqualTo(100);
        assertThat(small.cutPlan().cuts()).filteredOn(Cut::suggested).extracting(Cut::line).containsExactly("Eating Out");
        assertThat(small.cutPlan().cuts()).hasSizeGreaterThan(1);
    }

    @Test
    @DisplayName("Cut plan: wants trimmed by up to 35% first, then subscriptions, then a goal, then extra debt (with a warning)")
    void cutOrder() {
        Purchase big = new Purchase("Bike", 3000, LocalDate.of(2026, 12, 1), "cash", 0, false);
        Result r = AffordCheck.check(big, context());
        List<Cut> cuts = r.cutPlan().cuts();
        assertThat(cuts).extracting(Cut::kind).containsExactly("trim", "trim", "subscription", "subscription", "goal", "extraDebt");
        assertThat(cuts.get(0).label()).isEqualTo("Eating Out: $300 → $195 a month");
        assertThat(cuts.get(1).amount()).isEqualTo(35);                       // Entertainment $100 → $65
        assertThat(cuts.get(2).label()).isEqualTo("Pause Netflix");          // biggest first
        assertThat(cuts.get(2).applies()).isTrue();                          // the $30 Subscriptions line covers both
        assertThat(cuts.get(4).line()).isEqualTo("Savings - Trip");
        assertThat(cuts.get(5).note()).contains("Visa charges 24%");
        assertThat(r.cutPlan().cutsTotal()).isEqualTo(105 + 35 + 18 + 12 + 100 + 60);
    }

    @Test
    @DisplayName("Goal money delays the goal; then only the emergency fund (a warning, never a suggestion)")
    void goalsThenEmergency() {
        List<Goal> goals = List.of(new Goal("g1", "Trip", 3000, 800, LocalDate.of(2027, 6, 1), false));
        Result r = AffordCheck.check(buy(1000), context(budget(), Map.of("Eating Out", 300.0, "Entertainment", 100.0), goals, 2000));
        assertThat(r.verdict()).isEqualTo("delaysGoal");
        // $300 from this month; $700 from the trip, which gets $100 a month: about 7 months later
        assertThat(r.sources().get(2).label()).isEqualTo("$700 of your Trip savings (delays it about 7 months)");

        // with $200 of Eating Out still unspent, that's used before the goal
        Result skipFirst = AffordCheck.check(buy(1000), context(budget(), Map.of("Eating Out", 100.0, "Entertainment", 100.0), goals, 2000));
        assertThat(skipFirst.sources()).extracting(AffordCheck.Source::kind).containsExactly("unassigned", "savings", "wants", "goal");
        assertThat(skipFirst.sources().get(3).amount()).isEqualTo(500);

        Result e = AffordCheck.check(buy(2500), context(budget(), Map.of("Eating Out", 300.0, "Entertainment", 100.0), goals, 2000));
        assertThat(e.verdict()).isEqualTo("emergencyOnly");
        assertThat(e.warnings().get(0)).contains("would drop to $600 of its $6,000");

        Result never = AffordCheck.check(buy(9000), context(budget(), Map.of("Eating Out", 300.0, "Entertainment", 100.0), goals, 2000));
        assertThat(never.verdict()).isEqualTo("notYet");
        assertThat(never.readyBy()).isEqualTo("2029-05"); // $9,000 at $300 a month, starting now: 30 months
    }

    @Test
    @DisplayName("A card carried at 24% costs interest; pay in 4 warns when a month's payments don't fit")
    void paying() {
        Result card = AffordCheck.check(new Purchase("TV", 900, null, "card-balance", 24, false),
                context(budget(), Map.of("Eating Out", 300.0, "Entertainment", 100.0), List.of(), 0));
        assertThat(card.interest()).isGreaterThan(0);
        assertThat(card.warnings()).anyMatch(w -> w.contains("at 24% adds about $"));

        Result payIn4 = AffordCheck.check(new Purchase("TV", 1600, null, "pay-in-4", 0, false),
                context(budget(), Map.of("Eating Out", 300.0, "Entertainment", 100.0), List.of(), 0));
        assertThat(payIn4.payIn4()).hasSize(4).allMatch(p -> p.amount() == 400);
        // Nov 10 and Nov 24: $800 in November, but only $300 of room
        assertThat(payIn4.warnings()).anyMatch(w -> w.contains("$800 due in November 2026"));

        assertThat(AffordCheck.cardInterest(1000, 24, 10)).isNull(); // never paid off
    }

    @Test
    @DisplayName("Months are counted as the Plan tab counts a goal's date, so a Save-for-it goal isn't shown as short")
    void monthsMatchThePlanTab() {
        // Nov 24 → Feb 24 is 2 whole months from "now" (with the time of day) in the Plan tab
        assertThat(AffordCheck.monthsTo(LocalDate.of(2026, 11, 24), LocalDate.of(2027, 2, 24))).isEqualTo(2);
        assertThat(AffordCheck.monthsTo(LocalDate.of(2026, 11, 24), LocalDate.of(2027, 2, 25))).isEqualTo(3);
        assertThat(AffordCheck.monthsTo(LocalDate.of(2026, 11, 24), LocalDate.of(2026, 11, 30))).isEqualTo(1);
        // 4 months from Nov 24: the end of March
        assertThat(AffordCheck.goalDate(LocalDate.of(2026, 11, 24), 4)).isEqualTo(LocalDate.of(2027, 3, 31));
        assertThat(AffordCheck.monthsToSave(1500, 375)).isEqualTo(4);
    }

    @Test
    @DisplayName("The emergency fund's floor is never counted; ongoing costs get a warning by how they'd fit")
    void floorAndOngoing() {
        List<Goal> goals = List.of(new Goal("g1", "Trip", 3000, 800, LocalDate.of(2027, 6, 1), false));
        Map<String, Double> spentAll = Map.of("Eating Out", 300.0, "Entertainment", 100.0);
        Context noFloor = context(budget(), spentAll, goals, 2000);
        Context floor = new Context(noFloor.budget(), noFloor.spent(), noFloor.fixed(), noFloor.takeHome(), goals, 2000, 6000,
                24, "Visa", noFloor.subscriptions(), TODAY, 1500);
        // $2,500: $300 now + $800 trip + $1,400 of the fund; only $500 is above a $1,500 floor
        assertThat(AffordCheck.check(buy(2500), noFloor).verdict()).isEqualTo("emergencyOnly");
        Result withFloor = AffordCheck.check(buy(2500), floor);
        assertThat(withFloor.verdict()).isEqualTo("notYet");
        assertThat(withFloor.warnings()).anyMatch(w -> w.contains("above its $1,500 floor"));
        Result small = AffordCheck.check(buy(1400), floor);
        assertThat(small.verdict()).isEqualTo("emergencyOnly");
        assertThat(small.warnings()).anyMatch(w -> w.contains("would drop to $1,700") && w.contains("your floor is $1,500"));

        // $100 a month isn't assigned: $150 takes $50 of the $200 Savings
        Result car = AffordCheck.check(new Purchase("Car", 250, null, "cash", 0, false, 150), context());
        assertThat(car.warnings().get(0)).contains("Keeping Car costs about $150 a month").contains("come out of your Savings")
                .contains("$150 a month left to save instead of $300");
        Result pricey = AffordCheck.check(new Purchase("Car", 250, null, "cash", 0, false, 400), context());
        assertThat(pricey.warnings().get(0)).contains("doesn't have room").contains("lasting cuts");
        assertThat(AffordCheck.check(new Purchase("Car", 250, null, "cash", 0, false, 60), context()).warnings().get(0))
                .contains("money it doesn't assign yet");
    }

    @Test
    @DisplayName("A monthly cost fits from unassigned take-home, or needs lasting cuts; no budget: take the quiz")
    void monthlyAndNoBudget() {
        Result gym = AffordCheck.check(new Purchase("Gym", 50, null, "cash", 0, true), context());
        assertThat(gym.verdict()).isEqualTo("fits");
        assertThat(gym.headline()).isEqualTo("Yes, you can afford $50 a month");

        Result car = AffordCheck.check(new Purchase("Car payment", 450, null, "cash", 0, true), context());
        assertThat(car.verdict()).isEqualTo("notYet");
        assertThat(car.cutPlan().monthlyNeeded()).isEqualTo(150);
        assertThat(car.detail()).contains("lasting");

        assertThat(AffordCheck.check(buy(10), context(Map.of(), Map.of(), List.of(), 0)).verdict()).isEqualTo("noBudget");
    }
}
