package com.plotline.backend.commute;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Real prices from the U.S. Energy Information Administration (free; key in EIA_API_KEY):
 * the weekly average retail price of regular gas (a state's own where EIA publishes one, otherwise
 * its region's) and the latest monthly average residential electricity price in a state.
 * Empty when there's no key or EIA doesn't answer; the caller falls back to an AI estimate.
 */
@Component
public class EiaPrices {
    private static final Logger log = LoggerFactory.getLogger(EiaPrices.class);
    private static final String BASE = "https://api.eia.gov/v2/";

    /** states EIA publishes their own weekly gas price for */
    static final Map<String, String> STATE_SERIES = Map.of(
            "CA", "SCA", "CO", "SCO", "FL", "SFL", "MA", "SMA", "MN", "SMN",
            "NY", "SNY", "OH", "SOH", "TX", "STX", "WA", "SWA");

    /** every other state: its region (EIA's PADD regions; the West Coast without California) */
    static final Map<String, String> REGION_SERIES = regions();

    private static Map<String, String> regions() {
        Map<String, String> m = new LinkedHashMap<>();
        for (String s : "CT ME MA NH RI VT".split(" ")) m.put(s, "R1X");                 // New England
        for (String s : "DE DC MD NJ NY PA".split(" ")) m.put(s, "R1Y");                 // Central Atlantic
        for (String s : "FL GA NC SC VA WV".split(" ")) m.put(s, "R1Z");                 // Lower Atlantic
        for (String s : "IL IN IA KS KY MI MN MO NE ND SD OH OK TN WI".split(" ")) m.put(s, "R20"); // Midwest
        for (String s : "AL AR LA MS NM TX".split(" ")) m.put(s, "R30");                 // Gulf Coast
        for (String s : "CO ID MT UT WY".split(" ")) m.put(s, "R40");                    // Rocky Mountain
        for (String s : "AK AZ HI NV OR".split(" ")) m.put(s, "R5XCA");                  // West Coast except California
        m.put("CA", "R50");
        m.put("WA", "R5XCA");
        return m;
    }

    private static final Map<String, String> STATE_CODES = Map.ofEntries(
            Map.entry("alabama", "AL"), Map.entry("alaska", "AK"), Map.entry("arizona", "AZ"), Map.entry("arkansas", "AR"),
            Map.entry("california", "CA"), Map.entry("colorado", "CO"), Map.entry("connecticut", "CT"), Map.entry("delaware", "DE"),
            Map.entry("district of columbia", "DC"), Map.entry("florida", "FL"), Map.entry("georgia", "GA"), Map.entry("hawaii", "HI"),
            Map.entry("idaho", "ID"), Map.entry("illinois", "IL"), Map.entry("indiana", "IN"), Map.entry("iowa", "IA"),
            Map.entry("kansas", "KS"), Map.entry("kentucky", "KY"), Map.entry("louisiana", "LA"), Map.entry("maine", "ME"),
            Map.entry("maryland", "MD"), Map.entry("massachusetts", "MA"), Map.entry("michigan", "MI"), Map.entry("minnesota", "MN"),
            Map.entry("mississippi", "MS"), Map.entry("missouri", "MO"), Map.entry("montana", "MT"), Map.entry("nebraska", "NE"),
            Map.entry("nevada", "NV"), Map.entry("new hampshire", "NH"), Map.entry("new jersey", "NJ"), Map.entry("new mexico", "NM"),
            Map.entry("new york", "NY"), Map.entry("north carolina", "NC"), Map.entry("north dakota", "ND"), Map.entry("ohio", "OH"),
            Map.entry("oklahoma", "OK"), Map.entry("oregon", "OR"), Map.entry("pennsylvania", "PA"), Map.entry("rhode island", "RI"),
            Map.entry("south carolina", "SC"), Map.entry("south dakota", "SD"), Map.entry("tennessee", "TN"), Map.entry("texas", "TX"),
            Map.entry("utah", "UT"), Map.entry("vermont", "VT"), Map.entry("virginia", "VA"), Map.entry("washington", "WA"),
            Map.entry("west virginia", "WV"), Map.entry("wisconsin", "WI"), Map.entry("wyoming", "WY"));

    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private final ObjectMapper json = new ObjectMapper();

    /** "Virginia" or "VA" → "VA" (null if it isn't a state) */
    static String stateCode(String state) {
        if (state == null) return null;
        String s = state.strip();
        if (s.length() == 2 && REGION_SERIES.containsKey(s.toUpperCase(Locale.ROOT))) return s.toUpperCase(Locale.ROOT);
        return STATE_CODES.get(s.toLowerCase(Locale.ROOT));
    }

    /** the EIA weekly series for regular gas in a state (its own, else its region's); "_DPG" = dollars per gallon */
    static String gasSeries(String stateCode) {
        String area = STATE_SERIES.getOrDefault(stateCode, REGION_SERIES.get(stateCode));
        return area == null ? null : "EMM_EPMR_PTE_" + area + "_DPG";
    }

    protected String apiKey() {
        String key = System.getenv("EIA_API_KEY");
        return key == null || key.isBlank() ? null : key.strip();
    }

    public boolean configured() { return apiKey() != null; }

    /** at startup: whether real prices are on (never the key itself) */
    @jakarta.annotation.PostConstruct
    void announce() {
        log.info(configured() ? "EIA prices: on (EIA_API_KEY is set)" : "EIA prices: off (no EIA_API_KEY; gas and electricity are AI estimates)");
    }

    /** this week's average price of a gallon of regular gas for the state (or its region) */
    public Optional<Double> gasPerGallon(String state) {
        String code = stateCode(state);
        String series = code == null ? null : gasSeries(code);
        if (series == null || !configured()) return Optional.empty();
        Optional<Double> price = latest("petroleum/pri/gnd/data/", Map.of("frequency", "weekly", "data[0]", "value", "facets[series][]", series), "value")
                .filter(p -> p > 1 && p < 15);
        log.info("EIA gas price for {} ({}): {}", code, series, price.map(p -> "$" + p).orElse("none"));
        return price;
    }

    /** the latest monthly average residential electricity price in the state, per kWh */
    public Optional<Double> electricityPerKwh(String state) {
        String code = stateCode(state);
        if (code == null || !configured()) return Optional.empty();
        return latest("electricity/retail-sales/data/", Map.of("frequency", "monthly", "data[0]", "price",
                "facets[stateid][]", code, "facets[sectorid][]", "RES"), "price")
                .map(cents -> Math.round(cents * 10) / 1000.0)   // cents per kWh → dollars (14.73¢ → $0.147)
                .filter(p -> p > 0.03 && p < 1)
                .map(p -> { log.info("EIA electricity price for {}: ${}/kWh", code, p); return p; });
    }

    /** the newest row's value in an EIA answer ({"response": {"data": [{"period": ..., "value": 3.12}]}}) */
    static Optional<Double> newest(JsonNode answer, String field) {
        JsonNode row = answer.path("response").path("data").path(0);
        if (row.isMissingNode() || row.path(field).isNull() || row.path(field).isMissingNode()) return Optional.empty();
        double value = row.path(field).asDouble(Double.NaN);   // EIA sends numbers or numeric strings
        return Double.isNaN(value) ? Optional.empty() : Optional.of(Math.round(value * 1000) / 1000.0);
    }

    private Optional<Double> latest(String route, Map<String, String> params, String field) {
        Map<String, String> all = new LinkedHashMap<>(params);
        all.put("sort[0][column]", "period");
        all.put("sort[0][direction]", "desc");
        all.put("length", "1");
        all.put("api_key", apiKey());
        String query = all.entrySet().stream()
                .map(e -> URLEncoder.encode(e.getKey(), StandardCharsets.UTF_8) + "=" + URLEncoder.encode(e.getValue(), StandardCharsets.UTF_8))
                .collect(Collectors.joining("&"));
        try {
            HttpResponse<String> response = http.send(HttpRequest.newBuilder(URI.create(BASE + route + "?" + query))
                    .timeout(Duration.ofSeconds(15)).GET().build(), HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() != 200) {
                log.warn("EIA {} answered {}", route, response.statusCode()); // the URL has the key: not logged
                return Optional.empty();
            }
            return newest(json.readTree(response.body()), field);
        } catch (Exception e) {
            log.warn("EIA {} failed: {}", route, e.getClass().getSimpleName());
            return Optional.empty();
        }
    }
}
