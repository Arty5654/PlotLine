package com.plotline.backend.service;

import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import org.springframework.stereotype.Component;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.plotline.backend.external.ExternalDataClient;

import io.github.cdimascio.dotenv.Dotenv;

/**
 * USDA FoodData Central search, shared by food search and meal photos.
 *
 * Searches are POSTed as JSON: the same filters in the query string got intermittent 400s from
 * USDA's gateway. "Generic" foods are Foundation, SR Legacy and Survey (FNDDS) — described in detail
 * ("Beef, ground, 80% lean meat / 20% fat, raw", "Pasta, cooked") with values per 100 g; FNDDS foods
 * also carry household measures ("1 cup, cooked" = 140 g). "Branded" foods are store products.
 */
@Component
public class UsdaFoods {

    public static final List<String> GENERIC = List.of("Foundation", "SR Legacy", "Survey (FNDDS)");
    public static final List<String> BRANDED = List.of("Branded");

    private static final String SEARCH_URL = "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=";
    private static final Set<String> STOPWORDS = Set.of("and", "or", "with", "the", "of", "in", "a", "w", "without", "made", "nfs", "ns");

    private final ExternalDataClient client;
    private final String apiKey;
    private final ObjectMapper mapper = new ObjectMapper();
    private final Cache<String, JsonNode> cache = Caffeine.newBuilder()
            .expireAfterWrite(Duration.ofDays(1)).maximumSize(5_000).build();

    public UsdaFoods(ExternalDataClient client) {
        this.client = client;
        String key = System.getenv("USDA_FDC_API_KEY");
        if (key == null || key.isBlank()) key = Dotenv.configure().ignoreIfMissing().load().get("USDA_FDC_API_KEY");
        this.apiKey = key == null || key.isBlank() ? "DEMO_KEY" : key; // USDA's shared demo key, low limits
    }

    /** USDA's "foods" array for this search (cached for a day) */
    public JsonNode search(String query, List<String> dataTypes, int pageSize) throws IOException {
        String q = cleanQuery(query);
        if (q.isEmpty()) return mapper.createArrayNode();
        String cacheKey = String.join(",", dataTypes) + "|" + pageSize + "|" + q.toLowerCase(Locale.ROOT);
        JsonNode cached = cache.getIfPresent(cacheKey);
        if (cached != null) return cached;
        String body = mapper.writeValueAsString(Map.of("query", q, "dataType", dataTypes, "pageSize", pageSize));
        JsonNode foods = mapper.readTree(client.postJson(SEARCH_URL + URLEncoder.encode(apiKey, StandardCharsets.UTF_8), body))
                .path("foods");
        cache.put(cacheKey, foods);
        return foods;
    }

    /**
     * What people type, as USDA understands it: "80/20" is "80% lean" (USDA's own wording), and
     * symbols USDA's search rejects are dropped.
     */
    static String cleanQuery(String query) {
        String q = query == null ? "" : query.strip();
        q = q.replaceAll("(\\d{2})\\s*/\\s*\\d{1,2}", "$1% lean");
        q = q.replaceAll("[^\\p{L}\\p{N}%'\\- ]", " ");
        return q.replaceAll("\\s+", " ").strip();
    }

    public record Nutrition(double calories, double protein, double carbs, double fat) {
        public Nutrition scaled(double factor) {
            return new Nutrition(calories * factor, protein * factor, carbs * factor, fat * factor);
        }

        public Nutrition per100(double grams) { return scaled(100.0 / grams); }
    }

    /** calories (kcal) and macros (g) per 100 g; null if USDA doesn't give enough to go on */
    public static Nutrition per100g(JsonNode nutrients) {
        Double kcal208 = null, kcal958 = null, kcal957 = null, protein = null, carbs = null, fat = null;
        for (JsonNode n : nutrients) {
            String number = n.path("nutrientNumber").asText("");
            String unit = n.path("unitName").asText("");
            double value = n.path("value").asDouble(Double.NaN);
            if (Double.isNaN(value)) continue;
            switch (number) {
                case "208" -> { if (unit.equalsIgnoreCase("KCAL")) kcal208 = value; }
                case "958" -> kcal958 = value; // Atwater specific (Foundation foods)
                case "957" -> kcal957 = value; // Atwater general
                case "203" -> protein = value;
                case "205" -> carbs = value;
                case "204" -> fat = value;
                default -> { }
            }
        }
        if (protein == null && carbs == null && fat == null) return null;
        double p = protein == null ? 0 : protein, c = carbs == null ? 0 : carbs, f = fat == null ? 0 : fat;
        double kcal = kcal208 != null ? kcal208 : kcal958 != null ? kcal958 : kcal957 != null ? kcal957 : 4 * p + 4 * c + 9 * f;
        return new Nutrition(kcal, p, c, f);
    }

    /** lowercase words without filler, plural "s" trimmed: for comparing a search with a description */
    public static Set<String> tokens(String text) {
        Set<String> tokens = new HashSet<>();
        for (String word : text.toLowerCase(Locale.ROOT).split("[^a-z0-9]+")) {
            if (word.isEmpty() || STOPWORDS.contains(word) || (word.length() < 2 && !Character.isDigit(word.charAt(0)))) continue;
            tokens.add(word.length() > 3 && word.endsWith("s") && !word.endsWith("ss") ? word.substring(0, word.length() - 1) : word);
        }
        return tokens;
    }

    /** how many of the wanted words the description has (0 to 1) */
    public static double overlap(Set<String> wanted, Set<String> description) {
        if (wanted.isEmpty()) return 0;
        long hits = wanted.stream().filter(description::contains).count();
        return (double) hits / wanted.size();
    }
}
