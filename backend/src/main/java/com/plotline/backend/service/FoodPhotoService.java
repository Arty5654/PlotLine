package com.plotline.backend.service;

import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.service.UsdaFoods.Nutrition;

/**
 * Turns a meal photo into foods for the log. The AI identifies each food and estimates its weight;
 * calories and macros then come from USDA FoodData Central (generic foods, per 100 g) scaled to that
 * weight. USDA's own ranking isn't reliable (the first hit for "roasted chicken thigh" is chicken
 * skin), so the best of its top matches is picked by how well the description matches and how close
 * its calories are to the AI's estimate. With no good match, the AI's estimate is used.
 */
@Service
public class FoodPhotoService {
    private static final Logger log = LoggerFactory.getLogger(FoodPhotoService.class);

    private final OpenAIService openAI;
    private final UsdaFoods usda;
    private final ObjectMapper mapper = new ObjectMapper();

    public FoodPhotoService(OpenAIService openAI, UsdaFoods usda) {
        this.openAI = openAI;
        this.usda = usda;
    }

    /** the foods in the photo, ready for the app: id, name, servingSize, servings, grams, totals, and where the numbers came from */
    public List<Map<String, Object>> analyze(String base64Image, String note) throws Exception {
        JsonNode items = mapper.readTree(openAI.analyzeFoodFromImage(base64Image, note)).path("items");
        List<Map<String, Object>> foods = new ArrayList<>();
        for (JsonNode item : items) {
            Map<String, Object> food = toFood(item);
            if (food != null) foods.add(food);
        }
        return foods;
    }

    Map<String, Object> toFood(JsonNode item) {
        String name = item.path("name").asText("").strip();
        double grams = clamp(item.path("grams").asDouble(0), 0, 3000);
        if (name.isEmpty() || grams <= 0) return null;

        Nutrition estimate = new Nutrition(item.path("calories").asDouble(0), item.path("protein").asDouble(0),
                item.path("carbs").asDouble(0), item.path("fat").asDouble(0));
        Nutrition total = estimate;
        String basis = "estimate";
        String usdaName = null;

        Match match = bestUsdaMatch(item.path("usdaQuery").asText(name), estimate.per100(grams));
        if (match != null) {
            total = match.per100g().scaled(grams / 100.0);
            basis = "usda";
            usdaName = match.description();
        }

        String portion = item.path("portion").asText("").strip();
        Map<String, Object> food = new LinkedHashMap<>();
        food.put("id", UUID.randomUUID().toString().toUpperCase());
        food.put("name", name);
        food.put("servingSize", Math.round(grams) + " g" + (portion.isEmpty() ? "" : " (" + portion + ")"));
        food.put("servings", 1.0);
        food.put("grams", (double) Math.round(grams));
        food.put("calories", (double) Math.round(total.calories()));
        food.put("protein", round1(total.protein()));
        food.put("carbs", round1(total.carbs()));
        food.put("fat", round1(total.fat()));
        food.put("source", "photo");
        food.put("basis", basis);
        if (usdaName != null) food.put("usdaName", usdaName);
        return food;
    }

    // ── USDA ──────────────────────────────────────────────────────────────

    record Match(String description, Nutrition per100g) { }

    Match bestUsdaMatch(String query, Nutrition estimatePer100) {
        JsonNode results;
        try {
            results = usda.search(query, UsdaFoods.GENERIC, 10);
        } catch (IOException e) {
            log.warn("USDA lookup for \"{}\" failed ({}); using the AI's estimate", query, e.toString());
            return null;
        }
        Set<String> wanted = UsdaFoods.tokens(query);
        Match best = null;
        double bestScore = Double.NEGATIVE_INFINITY;
        for (JsonNode food : results) {
            Nutrition per100 = UsdaFoods.per100g(food.path("foodNutrients"));
            if (per100 == null) continue;
            String description = food.path("description").asText("");
            double overlap = UsdaFoods.overlap(wanted, UsdaFoods.tokens(description));
            if (overlap < 0.5) continue; // not the same food
            double ratio = estimatePer100.calories() > 0 && per100.calories() > 0
                    ? per100.calories() / estimatePer100.calories() : 1.0;
            if (estimatePer100.calories() > 0 && (ratio < 0.6 || ratio > 1.67)) continue; // likely the wrong entry
            double score = overlap - 0.5 * Math.abs(Math.log(ratio));
            if (score > bestScore) {
                bestScore = score;
                best = new Match(description, per100);
            }
        }
        return best;
    }

    private static double clamp(double v, double lo, double hi) { return Math.max(lo, Math.min(hi, v)); }

    private static double round1(double v) { return Math.round(v * 10) / 10.0; }
}
