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
                String key = normalize(ev.getName());
                grouped.computeIfAbsent(key, k -> new ArrayList<>()).add(ev);
            }

            List<RecurringChargePrompt> prompts = new ArrayList<>();
            for (var entry : grouped.entrySet()) {
                String key = entry.getKey();
                List<RecurringChargeRequest.ChargeEvent> list = entry.getValue();
                if (list.size() < 2) continue;

                Map<YearMonth, List<RecurringChargeRequest.ChargeEvent>> byMonth = list.stream()
                        .collect(Collectors.groupingBy(ev -> YearMonth.from(LocalDate.parse(ev.getDate(), ISO))));

                List<YearMonth> months = byMonth.keySet().stream().sorted().toList();
                int chain = trailingChain(months);
                if (chain < 2) continue; // need two consecutive months

                // Compare last two months for amount drift
                YearMonth lastMonth = months.get(months.size() - 1);
                YearMonth prevMonth = months.get(months.size() - 2);
                if (!prevMonth.plusMonths(1).equals(lastMonth)) continue;

                double avgLast = avgAmount(byMonth.get(lastMonth));
                double avgPrev = avgAmount(byMonth.get(prevMonth));
                if (!withinDrift(avgPrev, avgLast, 0.05)) continue;

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
            RecurringChargeRequest req = new RecurringChargeRequest();
            req.setUsername(username);
            req.setRemindAfterMonths(remindAfter);
            req.setCharges(fetchChargesFromPlaid(username, months));
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

            Map<String, String> snoozed = loadSnoozed(request.getUsername());
            snoozed.put(request.getSnoozeKey(), until.format(ISO));
            saveSnoozed(request.getUsername(), snoozed);

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

    private String normalize(String name) {
        return name == null ? "" : name.trim().toLowerCase();
    }

    private static double round2(double v) { return Math.round(v * 100.0) / 100.0; }

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
                    LocalDate date = LocalDate.parse(t.getDate().toString(), ISO);
                    events.add(new RecurringChargeRequest.ChargeEvent(
                            t.getName(),
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
