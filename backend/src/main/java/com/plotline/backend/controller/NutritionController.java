package com.plotline.backend.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.service.FoodPhotoService;
import com.plotline.backend.service.FoodSearchService;
import com.plotline.backend.service.NutritionService;
import com.plotline.backend.service.OpenAIService;
import com.plotline.backend.service.UserProfileService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.Base64;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/nutrition")
public class NutritionController {
    private static final Logger log = LoggerFactory.getLogger(NutritionController.class);


    @Autowired
    private NutritionService nutritionService;

    @Autowired
    private OpenAIService openAIService;

    @Autowired
    private UserProfileService userProfileService;

    @Autowired
    private FoodPhotoService foodPhotoService;

    @Autowired
    private FoodSearchService foodSearchService;

    private final ObjectMapper objectMapper = new ObjectMapper();

    // GET /api/nutrition/{username}/{dateKey}
    @GetMapping("/{username}/{dateKey}")
    public ResponseEntity<String> getEntry(@PathVariable String username, @PathVariable String dateKey) {
        try {
            String entry = nutritionService.getEntry(username, dateKey);
            if (entry == null) {
                return ResponseEntity.notFound().build();
            }
            return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(entry);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(jsonError(e.getMessage()));
        } catch (Exception e) {
            log.error("getEntry failed", e);
            return ResponseEntity.internalServerError().body(jsonError("Server error reading entry"));
        }
    }

    // PUT /api/nutrition/{username}/{dateKey}
    @PutMapping("/{username}/{dateKey}")
    public ResponseEntity<String> saveEntry(
            @PathVariable String username,
            @PathVariable String dateKey,
            @RequestBody String body) {
        try {
            nutritionService.saveEntry(username, dateKey, body);
            return ResponseEntity.ok("{\"success\": true}");
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(jsonError(e.getMessage()));
        } catch (Exception e) {
            log.error("saveEntry failed", e);
            return ResponseEntity.internalServerError().body(jsonError("Server error saving entry"));
        }
    }

    // GET /api/nutrition/{username}/user-data
    @GetMapping("/{username}/user-data")
    public ResponseEntity<String> getUserData(@PathVariable String username) {
        try {
            String data = nutritionService.getUserData(username);
            if (data == null) {
                return ResponseEntity.notFound().build();
            }
            return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(data);
        } catch (Exception e) {
            log.error("getUserData failed", e);
            return ResponseEntity.internalServerError().body(jsonError("Server error reading user data"));
        }
    }

    // PUT /api/nutrition/{username}/user-data
    @PutMapping("/{username}/user-data")
    public ResponseEntity<String> saveUserData(
            @PathVariable String username,
            @RequestBody String body) {
        try {
            nutritionService.saveUserData(username, body);
            return ResponseEntity.ok("{\"success\": true}");
        } catch (Exception e) {
            log.error("saveUserData failed", e);
            return ResponseEntity.internalServerError().body(jsonError("Server error saving user data"));
        }
    }

    // POST /api/nutrition/analyze-food - Analyze food photo with GPT-4o Vision
    /**
     * Food search: {"foods": [{id, name, brand?, kind ("generic" or "branded"), per100g {calories,
     * protein, carbs, fat}, portions [{label, grams}]}]}, generic foods first. (Replaces passing
     * USDA's raw results through /food-search, kept for older app versions.)
     */
    @GetMapping("/foods")
    public ResponseEntity<String> searchFoods(@RequestParam(name = "q", defaultValue = "") String query) {
        String q = query.strip();
        if (q.length() > 100) q = q.substring(0, 100);
        try {
            List<Map<String, Object>> foods = q.isEmpty() ? List.of() : foodSearchService.search(q);
            return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON)
                    .body(objectMapper.writeValueAsString(Map.of("foods", foods)));
        } catch (Exception e) {
            log.warn("Food search failed: {}", e.toString());
            return ResponseEntity.status(502).contentType(MediaType.APPLICATION_JSON)
                    .body(jsonError("Couldn't search foods. Please try again."));
        }
    }

    /**
     * The foods in a meal photo: a JSON array of {id, name, servingSize, servings, grams, calories,
     * protein, carbs, fat, source, basis ("usda" or "estimate"), usdaName}. `note` is optional extra
     * detail from the person ("chicken thigh, cooked in olive oil").
     */
    @PostMapping("/analyze-food")
    public ResponseEntity<String> analyzeFoodPhoto(
            @RequestParam("image") MultipartFile image,
            @RequestParam(value = "username", required = false) String username,
            @RequestParam(value = "note", required = false) String note) {
        try {
            String base64Image = Base64.getEncoder().encodeToString(image.getBytes());
            String clippedNote = note == null ? null : note.length() > 300 ? note.substring(0, 300) : note;
            List<Map<String, Object>> foods = foodPhotoService.analyze(base64Image, clippedNote);

            if (!foods.isEmpty() && username != null && !username.isEmpty()) {
                try {
                    userProfileService.incrementTrophy(username, "nutrition-photo", 1);
                } catch (Exception te) {
                    log.error("nutrition-photo trophy failed", te);
                }
            }
            return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(objectMapper.writeValueAsString(foods));
        } catch (Exception e) {
            log.error("analyzeFoodPhoto failed", e);
            return ResponseEntity.status(502).contentType(MediaType.APPLICATION_JSON)
                    .body(jsonError("Couldn't analyze the photo. Please try again."));
        }
    }

    private String jsonError(String message) {
        try {
            return objectMapper.writeValueAsString(Map.of("error", message));
        } catch (Exception e) {
            return "{\"error\": \"Unknown error\"}";
        }
    }
}
