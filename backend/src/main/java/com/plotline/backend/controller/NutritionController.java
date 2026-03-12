package com.plotline.backend.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.service.NutritionService;
import com.plotline.backend.service.OpenAIService;
import com.plotline.backend.service.UserProfileService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.Base64;
import java.util.Map;

@RestController
@RequestMapping("/api/nutrition")
public class NutritionController {

    @Autowired
    private NutritionService nutritionService;

    @Autowired
    private OpenAIService openAIService;

    @Autowired
    private UserProfileService userProfileService;

    private final ObjectMapper objectMapper = new ObjectMapper();

    // GET /api/nutrition/{username}/{dateKey}
    @GetMapping("/{username}/{dateKey}")
    public ResponseEntity<String> getEntry(@PathVariable String username, @PathVariable String dateKey) {
        String entry = nutritionService.getEntry(username, dateKey);
        if (entry == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(entry);
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
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("{\"error\": \"" + e.getMessage() + "\"}");
        }
    }

    // GET /api/nutrition/{username}/user-data
    @GetMapping("/{username}/user-data")
    public ResponseEntity<String> getUserData(@PathVariable String username) {
        String data = nutritionService.getUserData(username);
        if (data == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(data);
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
            return ResponseEntity.badRequest().body("{\"error\": \"" + e.getMessage() + "\"}");
        }
    }

    // POST /api/nutrition/analyze-food - Analyze food photo with GPT-4o Vision
    @PostMapping("/analyze-food")
    public ResponseEntity<String> analyzeFoodPhoto(
            @RequestParam("image") MultipartFile image,
            @RequestParam(value = "username", required = false) String username) {
        try {
            byte[] imageBytes = image.getBytes();
            String base64Image = Base64.getEncoder().encodeToString(imageBytes);

            String result = openAIService.analyzeFoodFromImage(base64Image);

            // Ensure we return valid JSON array
            result = result.trim();
            if (result.startsWith("```json")) {
                result = result.substring(7);
            } else if (result.startsWith("```")) {
                result = result.substring(3);
            }
            if (result.endsWith("```")) {
                result = result.substring(0, result.length() - 3);
            }
            result = result.trim();

            // Increment nutrition-photo trophy
            if (username != null && !username.isEmpty()) {
                try {
                    userProfileService.incrementTrophy(username, "nutrition-photo", 1);
                } catch (Exception te) {
                    te.printStackTrace();
                }
            }

            return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(result);
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.badRequest().body("[{\"error\": \"" + e.getMessage() + "\"}]");
        }
    }
}
