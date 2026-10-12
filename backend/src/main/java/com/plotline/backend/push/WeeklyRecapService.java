package com.plotline.backend.push;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.temporal.WeekFields;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.service.S3Service;

/**
 * Sunday 6 PM (each person's own time zone): "This week you spent $142 of your $300 budget."
 * The server sleeps when nobody uses the app, so a GitHub Actions timer calls run() every half hour
 * on Sundays and early Mondays (UTC); whoever is between 6 and 8 PM on Sunday and hasn't had this
 * week's recap gets it.
 */
@Service
public class WeeklyRecapService {
    private static final Logger log = LoggerFactory.getLogger(WeeklyRecapService.class);

    /** money moved to savings or investing isn't spending */
    static final Set<String> NOT_SPENDING = Set.of("savings", "brokerage", "roth ira", "401k contribution",
            "401(k) contribution", "emergency fund", "investments", "investing");

    private final JdbcTemplate jdbc;
    private final S3Service s3;
    private final PushService push;
    private final ObjectMapper json = new ObjectMapper();

    public WeeklyRecapService(JdbcTemplate jdbc, S3Service s3, PushService push) {
        this.jdbc = jdbc;
        this.s3 = s3;
        this.push = push;
    }

    /** sends this week's recap to everyone for whom it's now Sunday evening; returns how many */
    public int run(ZonedDateTime nowUtc) {
        int sent = 0;
        List<Map<String, Object>> people = jdbc.queryForList(
                "select username, max(time_zone) as time_zone from push_devices group by username");
        for (Map<String, Object> person : people) {
            String username = (String) person.get("username");
            ZoneId zone = zone((String) person.get("time_zone"));
            ZonedDateTime local = nowUtc.withZoneSameInstant(zone);
            if (local.getDayOfWeek() != DayOfWeek.SUNDAY || local.getHour() < 18 || local.getHour() >= 20) continue;
            String week = weekKey(local.toLocalDate());
            // one per week, even if the timer runs twice in the window
            int claimed = jdbc.update("insert into weekly_recaps (username, week) values (?, ?) on conflict do nothing", username, week);
            if (claimed == 0) continue;
            try {
                PushService.Message message = message(username, week);
                if (message != null) {
                    push.send(username, message);
                    sent++;
                }
            } catch (Exception e) {
                log.warn("Weekly recap for {} failed ({})", username, e.toString());
            }
        }
        return sent;
    }

    /** the recap for one person, or null when there's nothing to say (no budget and no spending) */
    PushService.Message message(String username, String week) throws Exception {
        double budget = spendingTotal(read("users/%s/weekly-budget-edited.json".formatted(username), "budget"));
        if (budget == 0) budget = spendingTotal(readMap("users/%s/weekly-budget.json".formatted(username)));
        double spent = spendingTotal(read("users/%s/costs/weekly/%s.json".formatted(username, week), "totals"));
        return text(spent, budget);
    }

    static PushService.Message text(double spent, double budget) {
        String title = "Your week in spending";
        if (budget > 0 && spent > budget) {
            return new PushService.Message(title, "You spent %s this week, %s over your %s budget.".formatted(
                    money(spent), money(spent - budget), money(budget)), "budget");
        }
        if (budget > 0) {
            return new PushService.Message(title, "You spent %s of your %s budget this week. %s left to spare.".formatted(
                    money(spent), money(budget), money(budget - spent)), "budget");
        }
        if (spent > 0) return new PushService.Message(title, "You spent " + money(spent) + " this week.", "budget");
        return null;
    }

    static double spendingTotal(Map<String, Object> amounts) {
        double total = 0;
        for (var entry : amounts.entrySet()) {
            if (NOT_SPENDING.contains(entry.getKey().toLowerCase(Locale.ROOT).strip())) continue;
            if (entry.getValue() instanceof Number n) total += n.doubleValue();
        }
        return total;
    }

    static String money(double amount) {
        return "$" + String.format(Locale.US, "%,.0f", amount);
    }

    /** Sunday-start weeks, like the spending screens ("2026-W42") */
    static String weekKey(LocalDate date) {
        LocalDate start = date.minusDays(date.getDayOfWeek().getValue() % 7);
        return "%04d-W%02d".formatted(start.get(WeekFields.SUNDAY_START.weekBasedYear()),
                start.get(WeekFields.SUNDAY_START.weekOfWeekBasedYear()));
    }

    private static ZoneId zone(String id) {
        try {
            return id == null ? ZoneId.of("America/New_York") : ZoneId.of(id);
        } catch (Exception e) {
            return ZoneId.of("America/New_York");
        }
    }

    private Map<String, Object> read(String key, String field) {
        Object inner = readMap(key).get(field);
        if (inner instanceof Map<?, ?> m) {
            @SuppressWarnings("unchecked") Map<String, Object> typed = (Map<String, Object>) m;
            return typed;
        }
        return Map.of();
    }

    private Map<String, Object> readMap(String key) {
        try {
            return json.readValue(s3.downloadFile(key), new TypeReference<Map<String, Object>>() {});
        } catch (Exception e) {
            return Map.of(); // nothing saved yet
        }
    }
}
