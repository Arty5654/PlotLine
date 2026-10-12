package com.plotline.backend.service;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.JsonNode;
import com.plotline.backend.service.UsdaFoods.Nutrition;

/**
 * Food search for the Nutrition page. Generic USDA foods come first, because their descriptions say
 * exactly what they are ("Beef, ground, 80% lean meat / 20% fat, raw", "Pasta, cooked"), then store
 * brands labeled with the brand. Searching everything at once used to return pages of store items all
 * named "GROUND BEEF" or "PASTA" with no lean %, raw/cooked or brand shown.
 */
@Service
public class FoodSearchService {
    private static final Logger log = LoggerFactory.getLogger(FoodSearchService.class);

    static final int GENERIC_RESULTS = 25;
    static final int BRANDED_RESULTS = 10;

    private final UsdaFoods usda;

    public FoodSearchService(UsdaFoods usda) {
        this.usda = usda;
    }

    /** generic foods (best matches first) then branded; throws if USDA can't be reached at all */
    public List<Map<String, Object>> search(String query) throws IOException {
        IOException failure = null;
        List<Map<String, Object>> generic = new ArrayList<>();
        try {
            generic = rankGeneric(query, usda.search(query, UsdaFoods.GENERIC, 50));
        } catch (IOException e) {
            failure = e;
            log.warn("Generic food search failed ({})", e.toString());
        }
        List<Map<String, Object>> branded = new ArrayList<>();
        try {
            branded = branded(usda.search(query, UsdaFoods.BRANDED, 25));
        } catch (IOException e) {
            if (failure != null) throw failure; // neither worked
            log.warn("Branded food search failed ({})", e.toString());
        }
        List<Map<String, Object>> results = new ArrayList<>(generic);
        results.addAll(branded);
        return results;
    }

    // ── generic ────────────────────────────────────────────────────────────

    /**
     * USDA's own order is weak ("rice" starts with "Dirty rice"), so: foods with every word you typed
     * first; among those, ones whose first word is what you typed ("Rice, white, ..." for "rice", not
     * "Dirty rice"), then
     * fewer extra words (plain foods before mixed dishes); USDA's order breaks ties.
     */
    List<Map<String, Object>> rankGeneric(String query, JsonNode foods) {
        Set<String> wanted = UsdaFoods.tokens(UsdaFoods.cleanQuery(query));
        record Scored(Map<String, Object> food, double score) { }
        List<Scored> scored = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        int rank = 0;
        for (JsonNode food : foods) {
            rank++;
            String description = food.path("description").asText("").strip();
            Nutrition per100 = UsdaFoods.per100g(food.path("foodNutrients"));
            if (description.isEmpty() || per100 == null || per100.calories() <= 0) continue;
            if (!seen.add(description.toLowerCase(Locale.ROOT))) continue;

            Set<String> words = UsdaFoods.tokens(description);
            double overlap = UsdaFoods.overlap(wanted, words);
            if (overlap < 0.5) continue;
            // USDA names generic foods "Beef, ground, ..." / "Rice, white, ...": the food comes first
            Set<String> firstWord = UsdaFoods.tokens(description.split("[ ,]")[0]);
            boolean startsWithIt = !firstWord.isEmpty() && wanted.containsAll(firstWord);
            // ...and best of all, the food itself before any detail ("Rice, white, cooked" for "rice",
            // not "Rice dressing"; "Chicken breast, grilled" for "chicken breast")
            boolean exactHead = UsdaFoods.tokens(description.split(",")[0]).equals(wanted);
            long extra = words.stream().filter(w -> !wanted.contains(w)).count();
            double score = overlap * 10 + (startsWithIt ? 5 : 0) + (exactHead ? 4 : 0)
                    - Math.min(extra, 10) * 0.3 - rank * 0.01;

            scored.add(new Scored(generic(food, description, per100), score));
        }
        return scored.stream()
                .sorted(Comparator.comparingDouble(Scored::score).reversed())
                .limit(GENERIC_RESULTS)
                .map(Scored::food)
                .toList();
    }

    private static Map<String, Object> generic(JsonNode food, String description, Nutrition per100) {
        List<Map<String, Object>> portions = new ArrayList<>();
        for (JsonNode measure : food.path("foodMeasures")) {
            String label = measure.path("disseminationText").asText("").strip();
            double grams = measure.path("gramWeight").asDouble(0);
            if (label.isEmpty() || grams <= 0 || label.equalsIgnoreCase("Quantity not specified")) continue;
            if (portions.stream().noneMatch(p -> p.get("label").equals(label))) portions.add(portion(label, grams));
        }
        return item("usda-" + food.path("fdcId").asText(), description, null, "generic", per100, portions);
    }

    // ── branded ────────────────────────────────────────────────────────────

    private static List<Map<String, Object>> branded(JsonNode foods) {
        List<Map<String, Object>> results = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (JsonNode food : foods) {
            if (results.size() >= BRANDED_RESULTS) break;
            Nutrition per100 = UsdaFoods.per100g(food.path("foodNutrients"));
            String name = titleCase(food.path("description").asText("").strip());
            if (name.isEmpty() || per100 == null || per100.calories() <= 0) continue;
            String brand = brand(food);
            // the same product listed several times
            if (!seen.add((name + "|" + brand + "|" + Math.round(per100.calories())).toLowerCase(Locale.ROOT))) continue;

            List<Map<String, Object>> portions = new ArrayList<>();
            double size = food.path("servingSize").asDouble(0);
            String unit = food.path("servingSizeUnit").asText("").toLowerCase(Locale.ROOT);
            if (size > 0 && (unit.equals("g") || unit.equals("grm") || unit.equals("ml"))) {
                String household = food.path("householdServingFullText").asText("").strip().toLowerCase(Locale.ROOT)
                        .replace("onz", "oz");
                String label = (household.isEmpty() ? "1 serving" : household) + " (" + Math.round(size) + " " + (unit.equals("ml") ? "ml" : "g") + ")";
                portions.add(portion(label, size)); // ml treated as g: close enough for most drinks
            }
            results.add(item("usda-" + food.path("fdcId").asText(), name, brand, "branded", per100, portions));
        }
        return results;
    }

    private static String brand(JsonNode food) {
        String name = food.path("brandName").asText("").strip();
        if (!name.isEmpty() && !name.equalsIgnoreCase("NOT A BRANDED ITEM")) return titleCase(name);
        String owner = food.path("brandOwner").asText("").strip();
        return owner.isEmpty() ? "Store brand" : owner;
    }

    /** "GROUND BEEF" → "Ground Beef" (brands often shout) */
    static String titleCase(String text) {
        if (!text.equals(text.toUpperCase(Locale.ROOT))) return text;
        StringBuilder out = new StringBuilder();
        for (String word : text.toLowerCase(Locale.ROOT).split(" ")) {
            if (out.length() > 0) out.append(' ');
            out.append(word.isEmpty() ? word : Character.toUpperCase(word.charAt(0)) + word.substring(1));
        }
        return out.toString();
    }

    // ── shape ──────────────────────────────────────────────────────────────

    private static Map<String, Object> portion(String label, double grams) {
        Map<String, Object> p = new LinkedHashMap<>();
        p.put("label", label);
        p.put("grams", Math.round(grams * 10) / 10.0);
        return p;
    }

    private static Map<String, Object> item(String id, String name, String brand, String kind, Nutrition per100,
                                            List<Map<String, Object>> portions) {
        Map<String, Object> per100g = new LinkedHashMap<>();
        per100g.put("calories", Math.round(per100.calories() * 10) / 10.0);
        per100g.put("protein", Math.round(per100.protein() * 10) / 10.0);
        per100g.put("carbs", Math.round(per100.carbs() * 10) / 10.0);
        per100g.put("fat", Math.round(per100.fat() * 10) / 10.0);
        Map<String, Object> item = new LinkedHashMap<>();
        item.put("id", id);
        item.put("name", name);
        if (brand != null) item.put("brand", brand);
        item.put("kind", kind);
        item.put("per100g", per100g);
        item.put("portions", portions);
        return item;
    }
}
