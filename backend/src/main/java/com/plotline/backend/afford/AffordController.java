package com.plotline.backend.afford;

import static com.plotline.backend.util.UsernameUtils.normalize;

import java.io.ByteArrayInputStream;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.plotline.backend.afford.AffordCheck.Context;
import com.plotline.backend.afford.AffordCheck.Cut;
import com.plotline.backend.afford.AffordCheck.Goal;
import com.plotline.backend.afford.AffordCheck.Purchase;
import com.plotline.backend.afford.AffordCheck.Result;
import com.plotline.backend.afford.AffordCheck.Subscription;
import com.plotline.backend.plan.BudgetFiles;
import com.plotline.backend.plan.BudgetLines;
import com.plotline.backend.costs.CostsWriter;
import com.plotline.backend.plan.PlanBudgetSync;
import com.plotline.backend.plan.PlanController;
import com.plotline.backend.service.FixedCosts;
import com.plotline.backend.service.OpenAIService;
import com.plotline.backend.service.S3Service;

/**
 * Budget → Plan → "Can I afford it?"
 *   POST /api/afford/{username}/check        {item, price, by?, payment?, apr?, monthly?} → the answer
 *   POST /api/afford/{username}/save-for-it  {item, price, by?, cuts: [budget lines], wishlistId?} → a
 *     Plan goal funded by those cuts (then Savings, then unassigned take-home); the goal remembers its
 *     cuts and the budget gets them back when it's reached or deleted (PlanBudgetSync)
 *   POST /api/afford/ongoing-costs           {item, price} → the AI's estimate of what it costs to keep
 *   POST /api/afford/{username}/bought       {goalId?, wishlistId?, item, price, category?} → logged to
 *     today's spending; the goal and wishlist item are closed (the goal's cuts end)
 */
@RestController
@RequestMapping("/api/afford")
public class AffordController {

    private final S3Service s3;
    private final BudgetFiles budgets;
    private final FixedCosts fixedCosts;
    private final OpenAIService openAI;
    private final CostsWriter costs;
    private final PlanBudgetSync sync;
    private final SubscriptionPauses pauses;
    private final ObjectMapper json = new ObjectMapper();

    public AffordController(S3Service s3, BudgetFiles budgets, FixedCosts fixedCosts, OpenAIService openAI,
                            CostsWriter costs, PlanBudgetSync sync, SubscriptionPauses pauses) {
        this.pauses = pauses;
        this.s3 = s3;
        this.budgets = budgets;
        this.fixedCosts = fixedCosts;
        this.openAI = openAI;
        this.costs = costs;
        this.sync = sync;
    }

    @PostMapping("/{username}/check")
    public ResponseEntity<?> check(@PathVariable String username, @RequestBody Map<String, Object> body) {
        Purchase p = purchase(body);
        if (p == null) return ResponseEntity.badRequest().body(Map.of("error", "Enter what it costs."));
        String user = normalize(username);
        return ResponseEntity.ok(AffordCheck.check(p, context(user, LocalDate.now())));
    }

    @PostMapping("/{username}/save-for-it")
    public ResponseEntity<?> saveForIt(@PathVariable String username, @RequestBody Map<String, Object> body) throws Exception {
        Purchase p = purchase(body);
        if (p == null || p.monthly()) return ResponseEntity.badRequest().body(Map.of("error", "Enter what it costs."));
        String user = normalize(username);
        LocalDate today = LocalDate.now();
        Context c = context(user, today);
        if (c.budget().isEmpty()) return ResponseEntity.badRequest().body(Map.of("error", "Take the budget quiz first."));
        Result r = AffordCheck.check(p, c);

        // the cuts they picked, in full (a pause pauses all of it): a budget line, or "subscription:<name>"
        Set<String> picked = new HashSet<>();
        if (body.get("cuts") instanceof List<?> list) list.forEach(o -> picked.add(String.valueOf(o).strip().toLowerCase(Locale.ROOT)));
        List<Cut> cuts = new ArrayList<>();
        List<String> pausedSubscriptions = new ArrayList<>();
        if (r.cutPlan() != null) {
            for (Cut cut : r.cutPlan().cuts()) {
                boolean isSub = "subscription".equals(cut.kind());
                boolean chosen = isSub ? cut.name() != null && picked.contains("subscription:" + cut.name().strip().toLowerCase(Locale.ROOT))
                                       : picked.contains(cut.line().toLowerCase(Locale.ROOT));
                if (!chosen) continue;
                if (isSub) pausedSubscriptions.add(cut.name());
                if (cut.applies()) cuts.add(cut);
            }
        }
        Map<String, Double> budget = new LinkedHashMap<>(c.budget());
        // several subscriptions lower the same line: one cut each (never more than the line has)
        Map<String, Double> byLine = new LinkedHashMap<>();
        cuts.forEach(cut -> byLine.merge(cut.line(), cut.amount(), Double::sum));
        byLine.replaceAll((line, amount) -> Math.min(amount, lineAmount(budget, line)));
        double fromCuts = byLine.values().stream().mapToDouble(Double::doubleValue).sum();

        double savings = Math.floor(lineAmount(budget, BudgetLines.SAVINGS));
        double unassigned = AffordCheck.unassigned(c);
        double room = fromCuts + savings + unassigned;
        if (room < 1) {
            return ResponseEntity.status(409).body(Map.of("error", "Your budget has no room to save for it yet. Pick a cut to make some."));
        }

        // a month's amount: enough by their date, else what the cuts and Savings allow. Months are
        // counted as the Plan tab counts them for a goal's date, so it doesn't show the goal as short.
        double price = Math.ceil(p.price());
        int months = p.by() != null ? AffordCheck.monthsTo(today, p.by()) : AffordCheck.monthsToSave(price, room);
        // at least what the cuts free: picked pauses are made in full, and all of it goes to the goal
        double monthly = Math.max(fromCuts, Math.min(room, Math.ceil(price / months)));
        LocalDate readyDate = p.by() != null && monthly * months >= price
                ? p.by() : AffordCheck.goalDate(today, AffordCheck.monthsToSave(price, monthly));
        YearMonth ready = YearMonth.from(readyDate);

        // the budget: lower the cut lines, then Savings; the rest is take-home that wasn't assigned
        ObjectNode plan = planNode(user);
        Map<String, Double> cutAmounts = new LinkedHashMap<>();
        double left = monthly;
        for (var e : byLine.entrySet()) {
            String key = find(budget, e.getKey());
            if (key == null || e.getValue() <= 0) continue;
            double t = Math.min(e.getValue(), budget.get(key));
            lower(budget, key, t);
            cutAmounts.put(key, t);
            left -= t;
            // a paused extra debt payment: the debt planner shows it paused too
            if (BudgetLines.isExtraDebt(key)) {
                plan.put("extraDebtPayment", Math.max(0, Math.round(plan.path("extraDebtPayment").asDouble() - t)));
            }
        }
        if (left > 0 && savings > 0) {
            double t = Math.min(left, savings);
            lower(budget, find(budget, BudgetLines.SAVINGS), t);
            left -= t;
        }

        // the goal (a name not already used)
        ArrayNode goals = plan.has("savingsGoals") && plan.get("savingsGoals").isArray()
                ? (ArrayNode) plan.get("savingsGoals") : plan.putArray("savingsGoals");
        String name = uniqueName(goals, p.item() == null || p.item().isBlank() ? "Purchase" : p.item().strip());
        ObjectNode goal = goals.addObject();
        goal.put("id", UUID.randomUUID().toString().toUpperCase(Locale.ROOT));
        goal.put("name", name);
        goal.put("target", price);
        goal.put("saved", 0);
        goal.put("targetDate", readyDate.toString());
        ArrayNode cutsNode = goal.putArray("cuts");
        cutAmounts.forEach((line, amount) -> cutsNode.addObject().put("line", line).put("amount", amount));

        budget.put(BudgetLines.goal(name), monthly);
        // saved for from the wishlist: the item shows the goal's progress
        String wishlistId = body.get("wishlistId") == null ? null : String.valueOf(body.get("wishlistId"));
        if (wishlistId != null) {
            for (JsonNode w : plan.path("wishlist")) {
                if (wishlistId.equals(w.path("id").asText()) && w instanceof ObjectNode wish) wish.put("goalId", goal.get("id").asText());
            }
        }
        byte[] bytes = json.writeValueAsBytes(plan);
        s3.uploadFile(PlanController.planKey(user), new ByteArrayInputStream(bytes), bytes.length);
        budgets.save(user, budget);
        fixedCosts.applyQuizBudget(user, budget);
        pauses.pause(user, pausedSubscriptions, goal.get("id").asText(), name);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("goal", goal);
        out.put("pausedSubscriptions", pausedSubscriptions);
        out.put("monthly", monthly);
        out.put("readyBy", ready.toString());
        out.put("budget", budget);
        return ResponseEntity.ok(out);
    }

    /** the AI's guess at what something costs to keep each month (a car: insurance, gas, upkeep) */
    @PostMapping("/ongoing-costs")
    public ResponseEntity<?> ongoingCosts(@RequestBody Map<String, Object> body) {
        String item = body.get("item") == null ? "" : String.valueOf(body.get("item")).strip();
        double price = body.get("price") instanceof Number n ? n.doubleValue() : 0;
        if (item.isEmpty() || item.length() > 60) return ResponseEntity.badRequest().body(Map.of("error", "Say what it is first."));
        try {
            String answer = openAI.estimateJson(ONGOING_INSTRUCTIONS, "Item: " + item + (price > 0 ? " (price $" + Math.round(price) + ")" : ""));
            JsonNode n = json.readTree(answer);
            List<Map<String, Object>> list = new ArrayList<>();
            for (JsonNode c : n.path("costs")) {
                String name = c.path("name").asText("").strip();
                double monthly = Math.round(c.path("monthly").asDouble());
                if (!name.isEmpty() && monthly > 0 && monthly <= 10_000 && list.size() < 5) {
                    list.add(Map.of("name", name.length() > 40 ? name.substring(0, 40) : name, "monthly", monthly));
                }
            }
            String note = n.path("note").asText("").strip();
            return ResponseEntity.ok(Map.of("costs", list, "note", note.length() > 200 ? note.substring(0, 200) : note));
        } catch (Exception e) {
            return ResponseEntity.status(502).body(Map.of("error", "Couldn't estimate that right now. Try again in a moment."));
        }
    }

    static final String ONGOING_INSTRUCTIONS = "You estimate the ongoing monthly costs of owning something a young adult in the US "
            + "is thinking of buying, on top of its price. Answer only JSON: {\"costs\": [{\"name\": \"Car insurance\", \"monthly\": 150}], "
            + "\"note\": \"one short sentence\"}. Up to 5 typical, realistic costs in whole US dollars a month (e.g. a car: insurance, gas, "
            + "maintenance, registration; a pet: food, vet, insurance; a gaming console: an online subscription). Spread yearly costs over "
            + "12 months. Never include the price itself or loan, lease or financing payments (how they pay is asked separately). "
            + "If it has no real ongoing costs (shoes, a laptop), return {\"costs\": [], \"note\": \"...\"} and say so.";

    /** "I bought it": today's spending gets it; the goal (its cuts end) and the wishlist item close */
    @PostMapping("/{username}/bought")
    public ResponseEntity<?> bought(@PathVariable String username, @RequestBody Map<String, Object> body) throws Exception {
        String user = normalize(username);
        String goalId = body.get("goalId") == null ? null : String.valueOf(body.get("goalId"));
        String wishlistId = body.get("wishlistId") == null ? null : String.valueOf(body.get("wishlistId"));
        ObjectNode before = planNode(user), plan = before.deepCopy();

        String item = body.get("item") == null ? "" : String.valueOf(body.get("item")).strip();
        double price = body.get("price") instanceof Number n ? n.doubleValue() : 0;
        boolean found = false;
        if (goalId != null && plan.path("savingsGoals") instanceof ArrayNode goals) {
            for (int i = 0; i < goals.size(); i++) {
                if (!goalId.equals(goals.get(i).path("id").asText())) continue;
                if (item.isEmpty()) item = goals.get(i).path("name").asText("");
                if (price <= 0) price = goals.get(i).path("target").asDouble();
                goals.remove(i);
                found = true;
                break;
            }
        }
        if (wishlistId != null && plan.path("wishlist") instanceof ArrayNode wishes) {
            for (int i = 0; i < wishes.size(); i++) {
                if (!wishlistId.equals(wishes.get(i).path("id").asText())) continue;
                if (item.isEmpty()) item = wishes.get(i).path("item").asText("");
                if (price <= 0) price = wishes.get(i).path("price").asDouble();
                wishes.remove(i);
                found = true;
                break;
            }
        }
        if (!found && (goalId != null || wishlistId != null)) {
            return ResponseEntity.status(404).body(Map.of("error", "That isn't in your plan anymore."));
        }
        if (price <= 0 || price > 10_000_000) return ResponseEntity.badRequest().body(Map.of("error", "Enter what it cost."));
        if (item.isEmpty()) item = "Purchase";
        if (item.length() > 60) item = item.substring(0, 60);

        // today's spending, in the category they picked (else Shopping, a want line, or Miscellaneous)
        String category = body.get("category") instanceof String c && !c.isBlank() ? c.strip() : defaultCategory(user);
        String today = LocalDate.now().toString();
        double amount = Math.round(price * 100) / 100.0;
        for (String type : List.of("weekly", "monthly")) costs.addDated(user, type, today, Map.of(category, amount));
        costs.storeTransaction(user, today, "afford-" + UUID.randomUUID(), item, amount, category, "manual");

        if (found) {
            PlanBudgetSync.restoreExtraDebt(before, plan);
            byte[] bytes = json.writeValueAsBytes(plan);
            s3.uploadFile(PlanController.planKey(user), new ByteArrayInputStream(bytes), bytes.length);
            sync.apply(user, before, plan);   // the goal's budget line goes; its cuts come back
            pauses.resume(user, PlanBudgetSync.endedGoals(before, plan));
        }
        return ResponseEntity.ok(Map.of("logged", amount, "category", category, "item", item));
    }

    private String defaultCategory(String user) {
        Map<String, Double> budget = budgets.monthly(user);
        String shopping = find(budget, "Shopping");
        if (shopping != null) return shopping;
        return budget.keySet().stream().filter(k -> AffordCheck.isWant(k, Set.of())).findFirst().orElse("Miscellaneous");
    }

    // ---------- reading what the check needs ----------

    private Purchase purchase(Map<String, Object> body) {
        double price = body.get("price") instanceof Number n ? n.doubleValue() : 0;
        if (price <= 0 || price > 10_000_000) return null;
        LocalDate by = null;
        if (body.get("by") instanceof String s && s.length() >= 10) {
            try { by = LocalDate.parse(s.substring(0, 10)); } catch (Exception ignored) { }
        }
        double apr = body.get("apr") instanceof Number n ? n.doubleValue() : 0;
        String item = body.get("item") == null ? "" : String.valueOf(body.get("item")).strip();
        if (item.length() > 60) item = item.substring(0, 60);
        double ongoing = 0;
        if (body.get("ongoingCosts") instanceof List<?> list) {
            for (Object o : list) {
                if (o instanceof Map<?, ?> m && m.get("monthly") instanceof Number n && n.doubleValue() > 0) ongoing += Math.min(10_000, n.doubleValue());
            }
        }
        return new Purchase(item, price, by, String.valueOf(body.getOrDefault("payment", "cash")), apr,
                Boolean.TRUE.equals(body.get("monthly")), ongoing);
    }

    Context context(String user, LocalDate today) {
        Map<String, Double> budget = budgets.monthly(user);
        List<Map<String, Object>> fixed = fixedCosts.load(user);

        // this month so far, fixed costs counted once (as Monthly Costs shows it)
        Map<String, Double> spent = new LinkedHashMap<>();
        Map<String, Object> month = read("users/%s/costs/monthly/%s.json".formatted(user, YearMonth.from(today)));
        if (month.get("totals") instanceof Map<?, ?> totals) {
            totals.forEach((k, v) -> { if (v instanceof Number n) spent.put(String.valueOf(k), n.doubleValue()); });
        }
        FixedCosts.countOnce(spent, fixed);
        Set<String> fixedLines = new HashSet<>();
        fixed.forEach(fc -> fixedLines.add(String.valueOf(fc.get("category")).strip().toLowerCase(Locale.ROOT)));

        JsonNode plan = planNode(user);
        List<Goal> goals = new ArrayList<>();
        for (JsonNode g : plan.path("savingsGoals")) {
            LocalDate date = null;
            try { if (g.path("targetDate").isTextual()) date = LocalDate.parse(g.get("targetDate").asText().substring(0, 10)); } catch (Exception ignored) { }
            goals.add(new Goal(g.path("id").asText(""), g.path("name").asText("").strip(), g.path("target").asDouble(),
                    g.path("saved").asDouble(), date, g.path("linkedAccountId").isTextual() && !g.get("linkedAccountId").asText().isBlank()));
        }
        double highestApr = 0;
        String highestName = "";
        for (JsonNode d : plan.path("debts")) {
            if (d.path("apr").asDouble() > highestApr && d.path("balance").asDouble() > 0) {
                highestApr = d.path("apr").asDouble();
                highestName = d.path("name").asText("debt");
            }
        }
        double spending = budget.entrySet().stream().filter(e -> !com.plotline.backend.controller.BudgetFit.isSaving(e.getKey()))
                .mapToDouble(Map.Entry::getValue).sum();
        JsonNode fund = plan.path("emergencyFund");
        // a linked fund's balance is in the bank: unknown here, so it's never offered
        double emergencySaved = fund.path("linkedAccountId").isTextual() ? 0 : fund.path("saved").asDouble();

        List<Subscription> subscriptions = new ArrayList<>();
        Map<String, Object> subs = read("users/%s/subscriptions.json".formatted(user));
        if (subs.get("subscriptions") instanceof Map<?, ?> items) {
            for (Object o : items.values()) {
                if (!(o instanceof Map<?, ?> item) || item.get("pausedFor") != null) continue;   // already paused
                double cost = 0;
                try { cost = Double.parseDouble(String.valueOf(item.get("cost")).replace("$", "").replace(",", "").strip()); } catch (Exception ignored) { }
                if (cost > 0) subscriptions.add(new Subscription(String.valueOf(item.get("name")), cost));
            }
        }
        return new Context(budget, spent, fixedLines, budgets.takeHome(user), goals, emergencySaved,
                Math.round(spending * fund.path("months").asInt(3)), highestApr, highestName, subscriptions, today,
                Math.max(0, fund.path("floor").asDouble(0)));
    }

    private ObjectNode planNode(String user) {
        try {
            byte[] data = s3.downloadFile(PlanController.planKey(user));
            JsonNode n = data == null || data.length == 0 ? null : json.readTree(data);
            return n instanceof ObjectNode o ? o : json.createObjectNode();
        } catch (Exception e) {
            return json.createObjectNode();
        }
    }

    private Map<String, Object> read(String key) {
        try {
            byte[] data = s3.downloadFile(key);
            if (data == null || data.length == 0) return Map.of();
            return json.readValue(data, new TypeReference<Map<String, Object>>() {});
        } catch (Exception e) {
            return Map.of();
        }
    }

    private static String uniqueName(ArrayNode goals, String name) {
        Set<String> used = new HashSet<>();
        goals.forEach(g -> used.add(g.path("name").asText("").strip().toLowerCase(Locale.ROOT)));
        String out = name;
        for (int i = 2; used.contains(out.toLowerCase(Locale.ROOT)); i++) out = name + " " + i;
        return out;
    }

    private static String find(Map<String, Double> budget, String line) {
        return budget.keySet().stream().filter(k -> k.equalsIgnoreCase(line)).findFirst().orElse(null);
    }

    private static double lineAmount(Map<String, Double> budget, String line) {
        String key = find(budget, line);
        return key == null ? 0 : budget.get(key);
    }

    private static void lower(Map<String, Double> budget, String key, double by) {
        double rest = budget.get(key) - by;
        if (rest >= 1) budget.put(key, rest); else budget.remove(key);
    }
}
