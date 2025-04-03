package com.plotline.backend.controller;

import com.plotline.backend.dto.HealthEntry;
import com.plotline.backend.service.HealthService;
import org.apache.http.HttpStatus;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.util.List;

@RestController
@RequestMapping("/api/health")
public class HealthController {

    @Autowired
    private HealthService healthService;

    // Get health entries for a specific week
    @GetMapping("/users/{username}/health-entries/{sundayDateString}/entries.json")
    public ResponseEntity<List<HealthEntry>> getHealthEntries(
            @PathVariable String username,
            @PathVariable String sundayDateString) {
        try {
            List<HealthEntry> entries = healthService.getHealthEntriesForWeek(username, sundayDateString);
            return ResponseEntity.ok(entries);
        } catch (IOException e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body(null);
        }
    }

    // Save or update health entries for a specific week
    @PutMapping("/users/{username}/health-entries/{sundayDateString}/entries.json")
    public ResponseEntity<String> saveHealthEntries(
            @PathVariable String username,
            @PathVariable String sundayDateString,
            @RequestBody List<HealthEntry> entries) {
        try {
            boolean success = healthService.saveHealthEntries(username, sundayDateString, entries);
            if (success) {
                return ResponseEntity.ok("Health entries saved successfully");
            } else {
                return ResponseEntity.status(400).body("Failed to save health entries");
            }
        } catch (IOException e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error saving health entries: " + e.getMessage());
        }
    }

    // Create a new health entry
    @PostMapping("/users/{username}/health-entries")
    public ResponseEntity<String> createHealthEntry(
            @PathVariable String username,
            @RequestBody HealthEntry healthEntry) {
        try {
            // Make sure the username in the path matches the one in the entry
            healthEntry.setUsername(username);
            
            String entryId = healthService.createHealthEntry(healthEntry);
            return ResponseEntity.ok(entryId);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body("Error: " + e.getMessage());
        } catch (IOException e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error creating health entry: " + e.getMessage());
        }
    }

    // Delete a health entry
    @DeleteMapping("/users/{username}/health-entries/{entryId}")
    public ResponseEntity<String> deleteHealthEntry(
            @PathVariable String username,
            @PathVariable String entryId) {
        try {
            boolean success = healthService.deleteHealthEntry(username, entryId);
            if (success) {
                return ResponseEntity.ok("Health entry deleted successfully");
            } else {
                return ResponseEntity.status(400).body("Failed to delete health entry");
            }
        } catch (IOException e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error deleting health entry: " + e.getMessage());
        }
    }

    // Get all health entries for a user
    @GetMapping("/users/{username}/health-entries")
    public ResponseEntity<List<HealthEntry>> getAllHealthEntries(@PathVariable String username) {
        try {
            List<HealthEntry> entries = healthService.getAllHealthEntries(username);
            return ResponseEntity.ok(entries);
        } catch (IOException e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body(null);
        }
    }

    // Get insights/statistics for a user's health data
    @GetMapping("/users/{username}/health-insights")
    public ResponseEntity<Object> getHealthInsights(@PathVariable String username) {
        try {
            Object insights = healthService.generateHealthInsights(username);
            return ResponseEntity.ok(insights);
        } catch (IOException e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body(null);
        }
    }
}