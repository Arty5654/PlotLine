package com.plotline.backend.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.plotline.backend.service.DietaryRestrictionsService;

import com.plotline.backend.dto.DietaryRestrictions;
import com.plotline.backend.dto.Allergies;

@RestController
@RequestMapping("/api/dietary-restrictions")
public class DietaryRestrictionsController {

    @Autowired
    private DietaryRestrictionsService dietaryRestrictionsService;

    // Get dietary restrictions
    @GetMapping("/get-dietary-restrictions/{username}")
    public ResponseEntity<DietaryRestrictions> getDietaryRestrictions(@PathVariable String username) {
        try {
            DietaryRestrictions dietaryRestrictions = dietaryRestrictionsService.getDietaryRestrictions(username);
            return ResponseEntity.ok(dietaryRestrictions);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(null);
        }
    }

    @PutMapping("/update-dietary-restrictions/{username}")
    public ResponseEntity<String> updateDietaryRestrictions(@PathVariable String username, @RequestBody DietaryRestrictions dietaryRestrictions) {
        try {
            dietaryRestrictionsService.updateDietaryRestrictions(username, dietaryRestrictions);
            return ResponseEntity.ok("Dietary restrictions fully updated for user: " + username);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body("Error: " + e.getMessage());
        }
    }
}
