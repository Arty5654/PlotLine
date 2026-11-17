package com.plotline.backend.commute;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.service.OpenAIService;

/**
 * The prices a commute estimate needs: gas and electricity in a state, a city's transit fares and
 * rideshare rates, and the tolls on a route. Gas and electricity are real prices from the U.S.
 * Energy Information Administration (EiaPrices: this week's gas average, the latest monthly
 * electricity price), checked again daily; the rest are AI estimates (no free source covers them),
 * as is gas or electricity when EIA can't answer. All are kept in Postgres per place so everyone
 * there gets the same numbers. The quiz shows them and every one can be changed.
 */
@Service
public class CommutePrices {
    private static final Logger log = LoggerFactory.getLogger(CommutePrices.class);

    enum Kind {
        GAS(Duration.ofDays(7), "{\"pricePerGallon\": 3.25}",
                "The average price of a gallon of regular gasoline right now in %s, USA."),
        ELECTRICITY(Duration.ofDays(30), "{\"pricePerKwh\": 0.17}",
                "The average residential electricity price per kWh right now in %s, USA."),
        TRANSIT(Duration.ofDays(30), "{\"monthlyPass\": 90, \"singleFare\": 2.5}",
                "The main public transit system serving %s: the price of an adult monthly unlimited pass and of one regular adult ride. If there's no monthly pass, give 0 for it."),
        RIDESHARE(Duration.ofDays(30), "{\"base\": 2.5, \"bookingFee\": 2.0, \"perMile\": 1.3, \"perMinute\": 0.35, \"minimumFare\": 8}",
                "Typical UberX rates in %s: base fare, booking/service fee, per mile, per minute, and minimum fare."),
        TOLLS(Duration.ofDays(90), "{\"oneWay\": 4.5}",
                "The typical toll cost for one weekday car trip on the usual toll route from %s, at rush hour, for a regular car with a transponder. If the usual route has no tolls, give 0.");

        final Duration maxAge;
        final String example;
        final String question;

        Kind(Duration maxAge, String example, String question) {
            this.maxAge = maxAge;
            this.example = example;
            this.question = question;
        }
    }

    private final JdbcTemplate jdbc;
    private final OpenAIService ai;
    private final EiaPrices eia;
    private final ObjectMapper json = new ObjectMapper();

    public CommutePrices(JdbcTemplate jdbc, OpenAIService ai, EiaPrices eia) {
        this.jdbc = jdbc;
        this.ai = ai;
        this.eia = eia;
    }

    /** the numbers for `kind` in `place`, from the cache or a fresh estimate (empty if that fails) */
    /** one lookup at a time per place: a second request waits and gets the first one's answer */
    private final java.util.concurrent.ConcurrentHashMap<String, Object> locks = new java.util.concurrent.ConcurrentHashMap<>();

    Map<String, Double> get(Kind kind, String place) {
        String key = place == null ? "" : place.toLowerCase(Locale.ROOT).replaceAll("\\s+", " ").strip();
        if (key.isEmpty()) return Map.of();
        // two parts of the quiz can ask at once: without this, one got EIA's price and the other (EIA
        // timing out) an AI guess that replaced it on the phone and in the saved prices
        synchronized (locks.computeIfAbsent(kind.name() + "|" + key, k -> new Object())) {
            return lookup(kind, place, key);
        }
    }

    private record Saved(Map<String, Double> numbers, Instant updatedAt) {
        boolean fromEia() { return numbers.containsKey("fromEIA"); }
        boolean newerThan(Duration age) { return updatedAt.isAfter(Instant.now().minus(age)); }
    }

    private Saved saved(Kind kind, String key) {
        List<Saved> rows = jdbc.query("select data, updated_at from price_estimates where kind = ? and place = ?",
                (rs, n) -> new Saved(parse(rs.getString("data")), rs.getTimestamp("updated_at").toInstant()),
                kind.name().toLowerCase(Locale.ROOT), key);
        return rows.isEmpty() ? null : rows.get(0);
    }

    private Map<String, Double> lookup(Kind kind, String place, String key) {
        Saved saved = saved(kind, key);
        // gas and electricity: EIA's real prices, checked again daily
        boolean fromEia = (kind == Kind.GAS || kind == Kind.ELECTRICITY) && eia.configured();
        if (fromEia) {
            if (saved != null && saved.fromEia() && saved.newerThan(Duration.ofDays(1))) return saved.numbers();
            var price = kind == Kind.GAS ? eia.gasPerGallon(place) : eia.electricityPerKwh(place);
            if (price.isPresent()) {
                Map<String, Double> numbers = new LinkedHashMap<>();
                numbers.put(kind == Kind.GAS ? "pricePerGallon" : "pricePerKwh", price.get());
                numbers.put("fromEIA", 1.0);   // the app says where the number came from
                save(kind, key, numbers);
                return numbers;
            }
            // EIA didn't answer (slow or down): its last price (up to two weeks old) beats a guess
            if (saved != null && saved.fromEia() && saved.newerThan(Duration.ofDays(14))) return saved.numbers();
        } else if (saved != null && saved.newerThan(kind.maxAge)) {
            return saved.numbers();
        }
        try {
            String answer = ai.estimateJson(
                    "You estimate US prices for a budgeting app. Answer with only a JSON object of plain numbers in US dollars, "
                            + "shaped exactly like " + kind.example + ". Use current typical prices; if unsure, give your best typical estimate.",
                    kind.question.formatted(place));
            Map<String, Double> numbers = parse(answer);
            boolean keepsEia = saved != null && saved.fromEia(); // an AI guess never replaces an EIA price
            if (!keepsEia && !numbers.isEmpty() && numbers.values().stream().allMatch(v -> v >= 0 && v < 1000)) save(kind, key, numbers);
            return numbers;
        } catch (Exception e) {
            log.warn("{} estimate for {} failed ({})", kind, key, e.toString());
            return Map.of();
        }
    }

    private void save(Kind kind, String key, Map<String, Double> numbers) {
        try {
            jdbc.update("""
                insert into price_estimates (kind, place, data, updated_at) values (?, ?, ?, now())
                on conflict (kind, place) do update set data = excluded.data, updated_at = now()
                """, kind.name().toLowerCase(Locale.ROOT), key, json.writeValueAsString(numbers));
        } catch (Exception e) {
            log.warn("Saving the {} price for {} failed ({})", kind, key, e.toString());
        }
    }

    private Map<String, Double> parse(String text) {
        try {
            Map<String, Object> raw = json.readValue(text, new TypeReference<Map<String, Object>>() {});
            Map<String, Double> out = new LinkedHashMap<>();
            raw.forEach((k, v) -> { if (v instanceof Number n) out.put(k, n.doubleValue()); });
            return out;
        } catch (Exception e) {
            return Map.of();
        }
    }

    /**
     * What a commute between two places needs for one way of getting there:
     * drive/carpool → gas (or electricity) and tolls; transit → fares; rideshare → rates.
     */
    public Map<String, Object> pricesFor(String mode, String homeState, String homeCity, String workPlace,
                                         boolean electric, boolean routeHasTolls) {
        Map<String, Object> out = new LinkedHashMap<>();
        String home = homeCity == null || homeCity.isBlank() ? homeState : homeCity + ", " + homeState;
        switch (mode == null ? "" : mode) {
            case "drive", "carpool-driver" -> {
                out.put(electric ? "electricity" : "gas", get(electric ? Kind.ELECTRICITY : Kind.GAS, homeState));
                if (routeHasTolls && workPlace != null && !workPlace.isBlank()) {
                    out.put("tolls", get(Kind.TOLLS, home + " to " + workPlace));
                }
            }
            case "transit" -> out.put("transit", get(Kind.TRANSIT, home));
            case "rideshare" -> out.put("rideshare", get(Kind.RIDESHARE, home));
            default -> { }
        }
        return out;
    }
}
