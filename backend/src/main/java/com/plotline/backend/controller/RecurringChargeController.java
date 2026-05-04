package com.plotline.backend.controller;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plaid.client.model.Transaction;
import com.plaid.client.model.TransactionsGetRequest;
import com.plaid.client.model.TransactionsGetRequestOptions;
import com.plaid.client.model.TransactionsGetResponse;
import com.plaid.client.request.PlaidApi;
import com.plotline.backend.dto.RecurringChargePrompt;
import com.plotline.backend.dto.RecurringChargeRequest;
import com.plotline.backend.dto.RecurringSnoozeRequest;
import com.plotline.backend.plaid.TokenStore;
import com.plotline.backend.service.S3Service;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;
import static com.plotline.backend.util.UsernameUtils.normalize;

@RestController
@RequestMapping("/api/subscriptions/recurring")
public class RecurringChargeController {

    private final S3Service s3Service;
    private final PlaidApi plaid;
    private final TokenStore tokenStore;
    private final ObjectMapper mapper = new ObjectMapper();
    private static final DateTimeFormatter ISO = DateTimeFormatter.ISO_LOCAL_DATE;
    private static final String SNOOZE_PATH = "users/%s/recurring_prompts_snoozed.json";

    public RecurringChargeController(S3Service s3Service, PlaidApi plaid, TokenStore tokenStore) {
        this.s3Service = s3Service;
        this.plaid = plaid;
        this.tokenStore = tokenStore;
    }

    /**
     * Analyze provided charge events for recurring patterns.
     */
    @PostMapping("/analyze")
    public ResponseEntity<?> analyze(@RequestBody RecurringChargeRequest request) {
        try {
            if (request.getUsername() == null || request.getUsername().isBlank()) {
                return ResponseEntity.badRequest().body(Map.of("error", "username is required"));
            }
            List<RecurringChargeRequest.ChargeEvent> events = request.getCharges();
            if (events == null || events.isEmpty()) {
                return ResponseEntity.ok(Map.of("prompts", List.of()));
            }

            int remindAfterMonths = request.getRemindAfterMonths() != null && request.getRemindAfterMonths() > 0
                    ? request.getRemindAfterMonths()
                    : 2;

            Map<String, String> snoozed = loadSnoozed(request.getUsername());
            LocalDate today = LocalDate.now();

            Map<String, List<RecurringChargeRequest.ChargeEvent>> grouped = new HashMap<>();
            for (RecurringChargeRequest.ChargeEvent ev : events) {
                if (ev == null || ev.getName() == null || ev.getDate() == null) continue;
                String key = normalizeMerchant(ev.getName());
                grouped.computeIfAbsent(key, k -> new ArrayList<>()).add(ev);
            }

            List<RecurringChargePrompt> prompts = new ArrayList<>();
            for (var entry : grouped.entrySet()) {
                String key = entry.getKey();
                List<RecurringChargeRequest.ChargeEvent> list = entry.getValue();
                if (list.size() < 2) continue;

                Map<YearMonth, List<RecurringChargeRequest.ChargeEvent>> byMonth = list.stream()
                        .collect(Collectors.groupingBy(ev -> YearMonth.from(LocalDate.parse(ev.getDate(), ISO))));

                // If any month has more than 2 charges, it's likely regular shopping, not a subscription
                boolean tooManyPerMonth = byMonth.values().stream().anyMatch(evs -> evs.size() > 2);
                if (tooManyPerMonth) continue;

                List<YearMonth> months = byMonth.keySet().stream().sorted().toList();
                int chain = trailingChain(months);
                if (chain < 3) continue; // need three consecutive months to be confident

                // Compare last two months for amount drift
                YearMonth lastMonth = months.get(months.size() - 1);
                YearMonth prevMonth = months.get(months.size() - 2);
                if (!prevMonth.plusMonths(1).equals(lastMonth)) continue;

                double avgLast = avgAmount(byMonth.get(lastMonth));
                double avgPrev = avgAmount(byMonth.get(prevMonth));
                if (!withinDrift(avgPrev, avgLast, 0.15)) continue;

                LocalDate lastSeen = list.stream()
                        .map(ev -> LocalDate.parse(ev.getDate(), ISO))
                        .max(Comparator.naturalOrder())
                        .orElse(today);

                String snoozeUntil = snoozed.get(key);
                if (snoozeUntil != null) {
                    try {
                        LocalDate snoozeDate = LocalDate.parse(snoozeUntil, ISO);
                        if (!today.isAfter(snoozeDate)) continue; // still snoozed
                    } catch (Exception ignored) { }
                }

                double avg = byMonth.values().stream()
                        .flatMap(List::stream)
                        .map(RecurringChargeRequest.ChargeEvent::getAmount)
                        .filter(Objects::nonNull)
                        .mapToDouble(Double::doubleValue)
                        .average()
                        .orElse(0.0);

                String prettyName = entry.getValue().get(0).getName();
                int day = lastSeen.getDayOfMonth();

                LocalDate nextReminder = today.plusMonths(remindAfterMonths);
                prompts.add(new RecurringChargePrompt(
                        key,
                        prettyName,
                        round2(avg),
                        day,
                        chain,
                        lastSeen.format(ISO),
                        nextReminder.format(ISO)
                ));
            }

            return ResponseEntity.ok(Map.of(
                    "prompts", prompts,
                    "remindAfterMonths", remindAfterMonths
            ));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to analyze recurring charges", "detail", e.getMessage()));
        }
    }

    /**
     * Convenience endpoint that gathers transactions from Plaid for the past N months
     * and runs the same recurring charge analysis.
     */
    @GetMapping("/analyze/{username}")
    public ResponseEntity<?> analyzeFromPlaid(
            @PathVariable String username,
            @RequestParam(name = "months", defaultValue = "6") int months,
            @RequestParam(name = "remindAfterMonths", defaultValue = "2") int remindAfter
    ) {
        try {
            String normUser = normalize(username);
            System.out.println("[RecurringCharge] Analyzing for user: " + normUser + " months=" + months);
            List<RecurringChargeRequest.ChargeEvent> charges = fetchChargesFromPlaid(normUser, months);
            System.out.println("[RecurringCharge] Fetched " + charges.size() + " charge events from Plaid");
            RecurringChargeRequest req = new RecurringChargeRequest();
            req.setUsername(normUser);
            req.setRemindAfterMonths(remindAfter);
            req.setCharges(charges);
            return analyze(req);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to fetch Plaid transactions", "detail", e.getMessage()));
        }
    }

    @PostMapping("/snooze")
    public ResponseEntity<?> snooze(@RequestBody RecurringSnoozeRequest request) {
        try {
            if (request.getUsername() == null || request.getUsername().isBlank()) {
                return ResponseEntity.badRequest().body(Map.of("error", "username is required"));
            }
            if (request.getSnoozeKey() == null || request.getSnoozeKey().isBlank()) {
                return ResponseEntity.badRequest().body(Map.of("error", "snoozeKey is required"));
            }
            int months = request.getMonths() != null && request.getMonths() > 0 ? request.getMonths() : 2;
            LocalDate until = LocalDate.now().plusMonths(months);

            String normUser = normalize(request.getUsername());
            Map<String, String> snoozed = loadSnoozed(normUser);
            snoozed.put(request.getSnoozeKey(), until.format(ISO));
            saveSnoozed(normUser, snoozed);

            return ResponseEntity.ok(Map.of(
                    "snoozedUntil", until.format(ISO),
                    "months", months
            ));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to snooze prompt", "detail", e.getMessage()));
        }
    }

    private Map<String, String> loadSnoozed(String username) {
        try {
            byte[] data = s3Service.downloadFile(String.format(SNOOZE_PATH, username));
            if (data == null || data.length == 0) return new HashMap<>();
            return mapper.readValue(data, new TypeReference<>() {});
        } catch (Exception e) {
            return new HashMap<>();
        }
    }

    private void saveSnoozed(String username, Map<String, String> snoozed) {
        try {
            String json = mapper.writeValueAsString(snoozed);
            ByteArrayInputStream in = new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8));
            s3Service.uploadFile(String.format(SNOOZE_PATH, username), in, json.length());
        } catch (Exception ignored) { }
    }

    private String normalizeMerchant(String name) {
        if (name == null) return "";
        // Strip common noise: transaction IDs, dates, locations, leading/trailing symbols
        String cleaned = name.trim().toLowerCase()
                .replaceAll("\\s*#\\d+.*", "")           // strip #12345 and everything after
                .replaceAll("\\s*\\d{2,}/\\d{2,}.*", "") // strip date patterns like 01/15
                .replaceAll("\\s*\\*+.*", "")             // strip * and everything after (common in bank txns)
                .replaceAll("\\s+", " ")                  // normalize whitespace
                .trim();
        return cleaned;
    }

    private static double round2(double v) { return Math.round(v * 100.0) / 100.0; }

    /**
     * Filter out Plaid transaction categories that are almost never subscriptions.
     * This eliminates false positives like grocery stores, restaurants, gas stations, etc.
     */
    private boolean isNonSubscriptionCategory(Transaction t) {
        if (t.getPersonalFinanceCategory() == null) return false;
        String detailed = t.getPersonalFinanceCategory().getDetailed();
        if (detailed == null) return false;
        String cat = detailed.toUpperCase();

        // Categories that are NOT subscriptions
        return cat.contains("GROCERIES") ||
               cat.contains("RESTAURANT") ||
               cat.contains("FOOD_AND_DRINK") ||
               cat.contains("COFFEE") ||
               cat.contains("FAST_FOOD") ||
               cat.contains("GAS_STATION") ||
               cat.contains("FUEL") ||
               cat.contains("PARKING") ||
               cat.contains("TAXI") ||
               cat.contains("RIDESHARE") ||
               cat.contains("PUBLIC_TRANSIT") ||
               cat.contains("ATM") ||
               cat.contains("TRANSFER") ||
               cat.contains("BANK_FEES") ||
               cat.contains("INTEREST") ||
               cat.contains("OVERDRAFT") ||
               cat.contains("INCOME") ||
               cat.contains("PAYROLL") ||
               cat.contains("GENERAL_MERCHANDISE") ||
               cat.contains("SUPERSTORES") ||
               cat.contains("PHARMACIES") ||
               cat.contains("CLOTHING") ||
               cat.contains("ELECTRONICS") ||
               cat.contains("CHARITABLE_GIVING") ||
               cat.contains("GOVERNMENT") ||
               cat.contains("TAX");
    }

    private double avgAmount(List<RecurringChargeRequest.ChargeEvent> list) {
        if (list == null || list.isEmpty()) return 0.0;
        return list.stream()
                .map(RecurringChargeRequest.ChargeEvent::getAmount)
                .filter(Objects::nonNull)
                .mapToDouble(Double::doubleValue)
                .average()
                .orElse(0.0);
    }

    private boolean withinDrift(double a, double b, double pct) {
        if (a == 0 || b == 0) return false;
        double diff = Math.abs(a - b);
        double base = Math.max(Math.abs(a), Math.abs(b));
        return (diff / base) <= pct;
    }

    private int trailingChain(List<YearMonth> months) {
        if (months.isEmpty()) return 0;
        List<YearMonth> sorted = months.stream().sorted().toList();
        int chain = 1;
        for (int i = sorted.size() - 2; i >= 0; i--) {
            YearMonth current = sorted.get(i);
            YearMonth next = sorted.get(i + 1);
            if (current.plusMonths(1).equals(next)) {
                chain++;
            } else {
                break;
            }
        }
        return chain;
    }

    private List<RecurringChargeRequest.ChargeEvent> fetchChargesFromPlaid(String username, int monthsBack) throws Exception {
        List<RecurringChargeRequest.ChargeEvent> events = new ArrayList<>();
        Map<String, String> tokens = tokenStore.listAccessTokens(username);
        if (tokens == null || tokens.isEmpty()) return events;

        LocalDate end = LocalDate.now();
        LocalDate start = end.minusMonths(Math.max(monthsBack, 1));

        for (String accessToken : tokens.values()) {
            int offset = 0;
            int pageSize = 200;
            boolean hasMore = true;
            while (hasMore) {
                TransactionsGetRequestOptions opts = new TransactionsGetRequestOptions()
                        .count(pageSize)
                        .offset(offset)
                        .includePersonalFinanceCategory(Boolean.TRUE);

                TransactionsGetRequest req = new TransactionsGetRequest()
                        .accessToken(accessToken)
                        .startDate(start)
                        .endDate(end)
                        .options(opts);

                TransactionsGetResponse res = plaid.transactionsGet(req).execute().body();
                if (res == null || res.getTransactions() == null) break;

                for (Transaction t : res.getTransactions()) {
                    if (Boolean.TRUE.equals(t.getPending())) continue;
                    if (t.getAmount() == null || t.getAmount().doubleValue() <= 0) continue;

                    // Skip categories that are almost never subscriptions
                    if (isNonSubscriptionCategory(t)) continue;

                    // Prefer merchantName (clean) over getName (raw bank description)
                    String txnName = t.getMerchantName() != null && !t.getMerchantName().isBlank()
                            ? t.getMerchantName() : t.getName();

                    LocalDate date = LocalDate.parse(t.getDate().toString(), ISO);
                    events.add(new RecurringChargeRequest.ChargeEvent(
                            txnName,
                            t.getAmount().doubleValue(),
                            date.format(ISO)
                    ));
                }

                offset += res.getTransactions().size();
                hasMore = res.getTotalTransactions() != null && offset < res.getTotalTransactions();
            }
        }
        return events;
    }
}
