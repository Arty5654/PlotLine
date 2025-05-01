package com.plotline.backend.controller;

import com.plotline.backend.service.MealService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/meals")
public class MealController {

    @Autowired
    private MealService mealService;

    // Endpoint to get all meals for a user
    @GetMapping("/{username}/all")
    public List<Map<String, Object>> getAllMeals(@PathVariable String username) {
        try {
            // Fetch all meals data for the user from S3
            return mealService.getAllMealsFromS3(username);
        } catch (IOException e) {
            e.printStackTrace();
            return List.of(Map.of("error", "Error retrieving meals: " + e.getMessage()));
        }
    }

    // Endpoint to get a specific meal by its mealID and username
    @GetMapping("/{username}/meals/{mealID}")
    public ResponseEntity<Map<String, Object>> getMealDetails(@PathVariable String username, @PathVariable String mealID) {
        try {
            Map<String, Object> meal = mealService.getMealFromS3(username, mealID);  // Fetch meal data from S3
            return ResponseEntity.ok(meal);
        } catch (IOException e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body(Map.of("error", "Error retrieving meal: " + e.getMessage()));
        }
    }
}
