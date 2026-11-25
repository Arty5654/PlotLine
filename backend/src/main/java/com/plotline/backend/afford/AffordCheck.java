package com.plotline.backend.afford;

import java.time.LocalDate;
import java.time.YearMonth;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import com.plotline.backend.controller.BudgetFit;
import com.plotline.backend.plan.BudgetLines;

/**
 * "Can I afford it?": a purchase checked against the budget and the Plan, with plain math (no AI),
 * using money least painful first:
 *   1. take-home the budget doesn't assign, and this month's Savings line
 *   2. skipping the rest of this month's wants (Eating Out, Entertainment...)
 *   3. a goal's saved money (it shows how long the goal is delayed)
 *   4. the emergency fund: only ever a warning
 * If it doesn't fit (or not by the date they want), a short-term cut plan: trim wants by up to a
 * third, pause subscriptions, pause a goal or the extra debt payment, with when it's ready.
 * Fixed costs, needs (rent, groceries...), debt minimums and investing lines are never cut.
 */
public final class AffordCheck {
    private AffordCheck() { }

    /** a want line can be trimmed by at most this share */
    static final double MAX_TRIM = 0.35;
    /** without a date, the cut plan aims to have it in this many months */
    static final int DEFAULT_MONTHS = 3;
    /** a debt at or above this APR (percent) gets a warning when its extra payment is paused */
    static final double HIGH_APR = 8;
    static final double WORK_HOURS_A_YEAR = 2080;

    // ---------- input ----------

    /**
     * @param by      when they want it (null: now)
     * @param payment cash | card-full | card-balance | pay-in-4
     * @param apr     the card's interest (percent), for card-balance
     * @param monthly a monthly cost (a gym, a car payment) instead of a one-time price
     * @param ongoing what it costs to keep each month (a car's insurance and gas), on top of the price
     */
    public record Purchase(String item, double price, LocalDate by, String payment, double apr, boolean monthly, double ongoing) {
        public Purchase(String item, double price, LocalDate by, String payment, double apr, boolean monthly) {
            this(item, price, by, payment, apr, monthly, 0);
        }
    }

    public record Goal(String id, String name, double target, double saved, LocalDate date, boolean linked) { }

    public record Subscription(String name, double cost) { }

    /**
     * @param budget     the monthly budget by line
     * @param spent      this month so far, by category
     * @param fixed      fixed categories (lower case): never trimmed
     * @param takeHome   a month (0: unknown)
     * @param highestApr the Plan's most expensive debt (percent; 0: none)
     * @param emergencyFloor what the emergency fund never goes below (set in the Plan; 0: none)
     */
    public record Context(Map<String, Double> budget, Map<String, Double> spent, Set<String> fixed, double takeHome,
                         List<Goal> goals, double emergencySaved, double emergencyTarget, double highestApr,
                         String highestAprName, List<Subscription> subscriptions, LocalDate today, double emergencyFloor) {
        public Context(Map<String, Double> budget, Map<String, Double> spent, Set<String> fixed, double takeHome,
                       List<Goal> goals, double emergencySaved, double emergencyTarget, double highestApr,
                       String highestAprName, List<Subscription> subscriptions, LocalDate today) {
            this(budget, spent, fixed, takeHome, goals, emergencySaved, emergencyTarget, highestApr, highestAprName,
                    subscriptions, today, 0);
        }

        /** the emergency fund above its floor: the most a purchase could ever take */
        double emergencyAvailable() { return Math.max(0, Math.floor(emergencySaved - emergencyFloor)); }
    }

    // ---------- output ----------

    /** money used, in order (`kind`: unassigned | savings | wants | goal | emergency) */
    public record Source(String kind, String label, double amount) { }

    /**
     * @param kind    trim | subscription | goal | extraDebt
     * @param line    the budget line it lowers ("" when it's advice only, like a subscription with no Subscriptions line)
     * @param applies   whether "Save for it" can make this change to the budget
     * @param suggested one of the cuts that close the gap (the rest are there to pick from)
     * @param name      what it pauses: the subscription's name (kind "subscription"), else null
     */
    public record Cut(String kind, String line, String label, double amount, String note, boolean applies, boolean suggested,
                      String name) {
        Cut(String kind, String line, String label, double amount, String note, boolean applies, boolean suggested) {
            this(kind, line, label, amount, note, applies, suggested, null);
        }
        Cut suggest() { return new Cut(kind, line, label, amount, note, applies, true, name); }
    }

    /** @param cutsTotal the suggested cuts, a month; @param readyBy "2027-02" with them (and what's set aside already) */
    public record CutPlan(double monthlyNeeded, int months, double cutsTotal, String readyBy, List<Cut> cuts) { }

    public record Payment(String date, double amount) { }

    /**
     * @param verdict    fits | fitsIfYouSkip | fitsByDate | delaysGoal | notYet | emergencyOnly | noBudget
     * @param readyBy    "2027-02" at what's set aside each month now (null: never / already fits)
     * @param interest   carrying it on a card until it's paid off (card-balance)
     * @param payIn4     the four payments (pay-in-4)
     */
    public record Result(String verdict, String headline, String detail, List<Source> sources,
                         double availableNow, double perMonth, String readyBy, double hoursOfWork,
                         Double interest, List<Payment> payIn4, CutPlan cutPlan, List<String> warnings) { }

    // ---------- the check ----------

    static String money(double v) { return "$" + String.format(Locale.US, "%,.0f", v); }
    private static final DateTimeFormatter MONTH = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.US);
    static String monthName(YearMonth m) { return m.atDay(1).format(MONTH); }

    private static String key(String s) { return s == null ? "" : s.strip().toLowerCase(Locale.ROOT); }

    private static double line(Map<String, Double> budget, String name) {
        return budget.entrySet().stream().filter(e -> key(e.getKey()).equals(key(name)))
                .mapToDouble(Map.Entry::getValue).findFirst().orElse(0);
    }

    /** a want: not saving or investing, not a need, not a fixed cost, not a debt */
    static boolean isWant(String line, Set<String> fixed) {
        return !BudgetFit.isSaving(line) && !BudgetFit.isNeed(line) && !fixed.contains(key(line))
                && !key(line).equals("subscriptions");
    }

    /** take-home the budget doesn't hand out */
    static double unassigned(Context c) {
        double total = c.budget().values().stream().mapToDouble(Double::doubleValue).sum();
        return c.takeHome() <= 0 ? 0 : Math.max(0, Math.floor(c.takeHome() - total));
    }

    /** what's left this month in each want line (largest first) */
    static Map<String, Double> wantsLeft(Context c) {
        Map<String, Double> out = new LinkedHashMap<>();
        c.budget().entrySet().stream().filter(e -> isWant(e.getKey(), c.fixed()))
                .sorted(Map.Entry.<String, Double>comparingByValue().reversed())
                .forEach(e -> {
                    double spent = line(c.spent(), e.getKey());
                    double left = Math.floor(Math.max(0, e.getValue() - spent));
                    if (left >= 1) out.put(e.getKey(), left);
                });
        return out;
    }

    public static Result check(Purchase p, Context c) {
        if (c.budget().isEmpty()) {
            return new Result("noBudget", "Take the budget quiz first",
                    "PlotLine needs your budget to know what you can spend.", List.of(), 0, 0, null, 0, null, null, null, List.of());
        }
        double price = Math.ceil(p.price());
        double unassigned = unassigned(c);
        double savings = Math.floor(line(c.budget(), BudgetLines.SAVINGS));
        double perMonth = unassigned + savings;
        double hours = c.takeHome() > 0 ? Math.round(price / (c.takeHome() * 12 / WORK_HOURS_A_YEAR) * 10) / 10.0 : 0;
        List<String> warnings = new ArrayList<>();

        if (p.monthly()) return monthlyCheck(p, c, price, unassigned, savings, hours);

        List<Source> sources = new ArrayList<>();
        double need = price;
        need = use(sources, "unassigned", "Take-home your budget doesn't assign yet", unassigned, need);
        need = use(sources, "savings", "This month's Savings", savings, need);
        double nowMoney = price - need;
        Map<String, Double> wants = wantsLeft(c);
        double wantsTotal = wants.values().stream().mapToDouble(Double::doubleValue).sum();

        String verdict, headline, detail;
        // months until their date, counted as the Plan tab counts a goal's (this month is the first)
        int monthsToDate = p.by() == null ? 0 : monthsTo(c.today(), p.by());
        String byName = p.by() == null ? null : monthName(YearMonth.from(p.by()));

        if (need <= 0) {
            verdict = "fits";
            headline = "Yes, you can afford it";
            detail = "It fits in this month's budget without changing anything else.";
        } else if (need <= wantsTotal) {
            verdict = "fitsIfYouSkip";
            List<String> names = new ArrayList<>();
            double left = need;
            for (var w : wants.entrySet()) {
                if (left <= 0) break;
                double t = Math.min(left, w.getValue());
                names.add(w.getKey());
                sources.add(new Source("wants", "Skip " + money(t) + " of this month's " + w.getKey(), t));
                left -= t;
            }
            headline = "Yes, if you skip some fun spending this month";
            detail = (nowMoney > 0 ? "Your Savings and unassigned money cover " + money(nowMoney) + ". The other " + money(need)
                    : "The " + money(need)) + " comes from not spending the rest of this month's " + String.join(" and ", names) + ".";
        } else if (p.by() != null && perMonth * monthsToDate >= price) {
            verdict = "fitsByDate";
            double each = Math.ceil(price / monthsToDate);
            sources.clear();
            sources.add(new Source("future", "Set aside " + money(each) + " a month until " + byName, price));
            headline = "Yes, by " + byName;
            detail = "Put " + money(each) + " a month from Savings toward it and you'll have " + money(price) + " by " + byName + ".";
        } else {
            // the rest of this month's wants, then goal money, then the emergency fund
            List<Source> goalSources = new ArrayList<>();
            double left = need;
            for (var w : wants.entrySet()) {
                if (left <= 0) break;
                double t = Math.min(left, w.getValue());
                goalSources.add(new Source("wants", "Skip " + money(t) + " of this month's " + w.getKey(), t));
                left -= t;
            }
            for (Goal g : c.goals().stream().filter(g -> !g.linked() && g.saved() > 0)
                    .sorted(Comparator.comparing(Goal::date, Comparator.nullsFirst(Comparator.<LocalDate>reverseOrder())))
                    .toList()) {
                if (left <= 0) break;
                double t = Math.min(left, Math.floor(g.saved()));
                double monthly = line(c.budget(), BudgetLines.goal(g.name()));
                String delay = monthly > 0 ? "delays it about " + (int) Math.ceil(t / monthly) + " month" + (Math.ceil(t / monthly) == 1 ? "" : "s")
                        : "it isn't in your budget, so it won't refill on its own";
                goalSources.add(new Source("goal", money(t) + " of your " + g.name() + " savings (" + delay + ")", t));
                left -= t;
            }
            if (left <= 0) {
                verdict = "delaysGoal";
                sources.addAll(goalSources);
                headline = "Yes, but it delays a goal";
                detail = "This month's money " + (wantsTotal > 0 ? "and skipping this month's fun spending cover " : "covers ")
                        + money(nowMoney + Math.min(need, wantsTotal)) + "; the rest would come out of what you've saved for a goal.";
            } else if (left <= c.emergencyAvailable()) {
                verdict = "emergencyOnly";
                sources.addAll(goalSources);
                sources.add(new Source("emergency", money(left) + " of your emergency fund", left));
                headline = "Only by dipping into your emergency fund";
                detail = "That money is for surprises like a car repair or losing your job. It's better to wait and save for this.";
                warnings.add("Your emergency fund would drop to " + money(c.emergencySaved() - left)
                        + (c.emergencyTarget() > 0 ? " of its " + money(c.emergencyTarget()) + " goal" : "")
                        + (c.emergencyFloor() > 0 ? " (your floor is " + money(c.emergencyFloor()) + ")." : "."));
            } else {
                verdict = "notYet";
                headline = "Not yet";
                if (c.emergencyFloor() > 0 && c.emergencySaved() > c.emergencyFloor()) {
                    warnings.add("Even your emergency fund above its " + money(c.emergencyFloor()) + " floor wouldn't cover it.");
                }
                detail = perMonth > 0
                        ? "Your budget sets aside " + money(perMonth) + " a month you could use for it."
                        : "Your budget doesn't leave money for it each month yet. The cuts below can make room.";
            }
        }

        // when it's ready at what's set aside now (if it doesn't fit yet), counted like the Plan tab
        // counts a goal: this month's money is the first of the months
        String readyBy = null;
        boolean fitsNow = verdict.equals("fits") || verdict.equals("fitsIfYouSkip");
        if (!fitsNow && perMonth > 0) {
            readyBy = readyMonth(c.today(), price, perMonth);
            if (verdict.equals("notYet")) {
                headline = "Not yet: about " + monthName(YearMonth.parse(readyBy));
                detail += " At that pace you'll have " + money(price) + " around " + monthName(YearMonth.parse(readyBy)) + ".";
            }
        }

        // the cut plan whenever it doesn't simply fit (suggested cuts only when there's a gap to close;
        // the rest are there for "Save for it")
        CutPlan cutPlan = null;
        if (!verdict.equals("fits")) {
            int months = p.by() != null ? monthsToDate : DEFAULT_MONTHS;
            double monthlyNeeded = Math.max(0, Math.ceil(price / months - perMonth));
            cutPlan = cutPlan(c, monthlyNeeded, months, price, nowMoney, perMonth);
        }

        // paying for it
        Double interest = null;
        List<Payment> payIn4 = null;
        if ("card-balance".equals(p.payment())) {
            double apr = p.apr() > 0 ? p.apr() : 24;
            // paid off at what's set aside each month (with the cuts, if any)
            double pay = perMonth + (cutPlan == null ? 0 : cutPlan.cutsTotal());
            interest = pay <= 0 ? null : cardInterest(price, apr, pay);
            if (interest == null) {
                warnings.add("Your budget has no room to pay the card off, so the balance would keep growing at " + trim(apr) + "%.");
            } else if (interest >= 1) {
                warnings.add("Carrying it on a card at " + trim(apr) + "% adds about " + money(interest)
                        + " in interest if you pay " + money(pay) + " a month.");
            }
        } else if ("pay-in-4".equals(p.payment())) {
            payIn4 = new ArrayList<>();
            double each = Math.ceil(price / 4 * 100) / 100;
            Map<YearMonth, Double> byMonth = new LinkedHashMap<>();
            for (int i = 0; i < 4; i++) {
                LocalDate d = c.today().plusWeeks(2L * i);
                payIn4.add(new Payment(d.toString(), each));
                byMonth.merge(YearMonth.from(d), each, Double::sum);
            }
            YearMonth thisMonth = YearMonth.from(c.today());
            for (var m : byMonth.entrySet()) {
                double room = m.getKey().equals(thisMonth) ? nowMoney + wantsTotal : perMonth;
                if (m.getValue() > room + 0.5) {
                    warnings.add("The " + money(m.getValue()) + " due in " + monthName(m.getKey()) + " is more than your budget has room for ("
                            + money(room) + "). A missed payment can mean late fees.");
                }
            }
        } else if ("card-full".equals(p.payment()) && !fitsNow) {
            warnings.add("Only put it on a card you pay off in full if the money is there when the bill comes.");
        }

        ongoingWarning(p, unassigned, savings, warnings);
        return new Result(verdict, headline, detail, sources, nowMoney, perMonth, readyBy, hours,
                interest, payIn4, cutPlan, warnings);
    }

    /** what it costs to keep each month (a car's insurance and gas) has to fit every month too */
    static void ongoingWarning(Purchase p, double unassigned, double savings, List<String> warnings) {
        double ongoing = Math.ceil(p.ongoing());
        if (ongoing < 1) return;
        String it = p.item() == null || p.item().isBlank() ? "it" : p.item();
        if (ongoing <= unassigned) {
            warnings.add(0, "Keeping " + it + " costs about " + money(ongoing) + " a month. Your budget has room for that in money it doesn't assign yet.");
        } else if (ongoing <= unassigned + savings) {
            warnings.add(0, "Keeping " + it + " costs about " + money(ongoing) + " a month. That would come out of your Savings: "
                    + money(Math.max(0, unassigned + savings - ongoing)) + " a month left to save instead of " + money(unassigned + savings) + ".");
        } else {
            warnings.add(0, "Keeping " + it + " costs about " + money(ongoing) + " a month, and your budget doesn't have room for that yet. "
                    + "You'd need lasting cuts, not just short-term ones.");
        }
    }

    /** a monthly cost (a gym, a phone upgrade): it has to fit every month */
    private static Result monthlyCheck(Purchase p, Context c, double price, double unassigned, double savings, double hours) {
        List<Source> sources = new ArrayList<>();
        double need = use(sources, "unassigned", "Take-home your budget doesn't assign yet", unassigned, price);
        need = use(sources, "savings", "Your monthly Savings", savings, need);
        String verdict, headline, detail;
        CutPlan cuts = null;
        if (need <= 0 && sources.size() == 1) {
            verdict = "fits";
            headline = "Yes, you can afford " + money(price) + " a month";
            detail = "Your budget has " + money(unassigned) + " a month it doesn't assign yet.";
        } else if (need <= 0) {
            verdict = "fits";
            headline = "Yes, but it comes out of your Savings";
            detail = "You'd save " + money(savings - (price - unassigned)) + " a month instead of " + money(savings) + ".";
        } else {
            verdict = "notYet";
            headline = "Not without changing your budget";
            detail = "This is every month, so the cuts below would be lasting, not just for a few months.";
            cuts = cutPlan(c, need, 1, need, 0, 0);
        }
        return new Result(verdict, headline, detail, sources, unassigned + savings, unassigned + savings, null,
                hours, null, null, cuts, List.of());
    }

    private static double use(List<Source> sources, String kind, String label, double available, double need) {
        if (need <= 0 || available <= 0) return need;
        double t = Math.min(need, available);
        sources.add(new Source(kind, label, t));
        return need - t;
    }

    /** cuts that make `monthlyNeeded` a month, mildest first */
    static CutPlan cutPlan(Context c, double monthlyNeeded, int months, double price, double nowMoney, double perMonth) {
        List<Cut> candidates = new ArrayList<>();
        // 1. trim wants (largest first), up to a third each, in $5 steps
        for (var e : c.budget().entrySet().stream().filter(e -> isWant(e.getKey(), c.fixed()))
                .sorted(Map.Entry.<String, Double>comparingByValue().reversed()).toList()) {
            double cut = Math.floor(e.getValue() * MAX_TRIM / 5) * 5;
            if (cut >= 10) {
                candidates.add(new Cut("trim", e.getKey(), e.getKey() + ": " + money(e.getValue()) + " → " + money(e.getValue() - cut) + " a month",
                        cut, null, true, false));
            }
        }
        // 2. pause subscriptions (lowers the Subscriptions line, if there is one)
        double subscriptionsLine = line(c.budget(), "Subscriptions");
        double subsCut = 0;
        for (Subscription s : c.subscriptions().stream().sorted(Comparator.comparingDouble(Subscription::cost).reversed()).toList()) {
            if (s.cost() < 1) continue;
            boolean applies = subscriptionsLine - subsCut >= s.cost();
            if (applies) subsCut += s.cost();
            candidates.add(new Cut("subscription", applies ? "Subscriptions" : "", "Pause " + s.name(), Math.round(s.cost()),
                    "Cancel or pause it in the app you pay through; it's marked paused in Track Subscriptions until you have it.",
                    applies, false, s.name()));
        }
        // 3. pause a goal's monthly amount (no date first, then the furthest date; reached goals skipped)
        record GoalLine(String line, String name, LocalDate date, double amount) { }
        List<GoalLine> goalLines = new ArrayList<>();
        for (var e : c.budget().entrySet()) {
            if (!BudgetLines.isGoal(e.getKey()) || e.getValue() < 1) continue;
            String name = e.getKey().substring(BudgetLines.GOAL_PREFIX.length()).strip();
            Goal g = c.goals().stream().filter(x -> x.name().equalsIgnoreCase(name)).findFirst().orElse(null);
            if (g != null && g.target() > 0 && g.saved() >= g.target()) continue;
            goalLines.add(new GoalLine(e.getKey(), name, g == null ? null : g.date(), Math.floor(e.getValue())));
        }
        goalLines.sort(Comparator.comparing(GoalLine::date, Comparator.nullsFirst(Comparator.<LocalDate>reverseOrder())));
        for (GoalLine g : goalLines) {
            candidates.add(new Cut("goal", g.line(), "Pause your " + g.name() + " goal", g.amount(),
                    "It's delayed by the months it's paused.", true, false));
        }
        // 4. pause the extra debt payment
        double extra = Math.floor(line(c.budget(), BudgetLines.EXTRA_DEBT));
        if (extra >= 1) {
            candidates.add(new Cut("extraDebt", BudgetLines.EXTRA_DEBT, "Pause your extra debt payment", extra,
                    c.highestApr() >= HIGH_APR ? "Your " + c.highestAprName() + " charges " + trim(c.highestApr())
                            + "% interest, so pausing this costs you interest." : null, true, false));
        }

        // all of them, the ones that close the gap marked (mildest first)
        List<Cut> all = new ArrayList<>();
        double total = 0;
        for (Cut cut : candidates) {
            if (total < monthlyNeeded) {
                all.add(cut.suggest());
                total += cut.amount();
            } else {
                all.add(cut);
            }
        }
        double pace = perMonth + total;
        String readyBy = pace > 0 ? readyMonth(c.today(), price, pace) : null;
        return new CutPlan(monthlyNeeded, months, total, readyBy, all);
    }

    /**
     * whole months from today to `by`, at least 1. The Plan tab counts from now (with the time of
     * day) to midnight on the date, so a date on today's day of the month is one month short: this
     * counts from tomorrow to match.
     */
    static int monthsTo(LocalDate today, LocalDate by) {
        return (int) Math.max(1, ChronoUnit.MONTHS.between(today.plusDays(1), by));
    }

    /** the goal date for saving over `months`: the end of that month, so the Plan tab counts all of them */
    static LocalDate goalDate(LocalDate today, int months) {
        LocalDate d = today.plusMonths(months);
        return d.withDayOfMonth(d.lengthOfMonth());
    }

    /** months to save `price` at `pace` a month, starting this month */
    static int monthsToSave(double price, double pace) {
        return (int) Math.max(1, Math.ceil(price / pace));
    }

    /** "2027-03": the month it's saved, at `pace` a month from today (as the Plan tab dates a goal) */
    static String readyMonth(LocalDate today, double price, double pace) {
        return YearMonth.from(today.plusMonths(monthsToSave(price, pace))).toString();
    }

    /** interest paying `price` off at `pay` a month on a card at `apr`% (null: never paid off) */
    static Double cardInterest(double price, double apr, double pay) {
        double balance = price, interest = 0, rate = apr / 100 / 12;
        for (int i = 0; i < 600 && balance > 0.005; i++) {
            double charge = balance * rate;
            if (pay <= charge) return null;
            interest += charge;
            balance = balance + charge - pay;
        }
        return (double) Math.round(interest);
    }

    static String trim(double v) {
        return java.math.BigDecimal.valueOf(Math.round(v * 100) / 100.0).stripTrailingZeros().toPlainString();
    }
}
