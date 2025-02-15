package com.plotline.backend.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.WeeklyMonthlyCostRequest;
import com.plotline.backend.service.S3Service;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;

@RestController
@RequestMapping("/api/costs")
public class WeeklyMonthlyCostController {

    @Autowired
    private S3Service s3Service;

    @PostMapping
    public ResponseEntity<String> saveWeeklyMonthlyCosts(@RequestBody WeeklyMonthlyCostRequest request) {
        try {
            // Convert request object to JSON string
            String jsonData = new ObjectMapper().writeValueAsString(request);

            // Convert string to InputStream for S3 upload
            ByteArrayInputStream inputStream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));

            // Generate a unique S3 key per user
            String key = "users/" + request.getUsername() + "/" + request.getType() + "_costs.json";

            // Upload the file to S3 using S3Service
            s3Service.uploadFile(key, inputStream, jsonData.length());

            return ResponseEntity.ok("Weekly/Monthly costs saved successfully.");
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error saving data: " + e.getMessage());
        }
    }

    @GetMapping("/{username}/{type}")
    public ResponseEntity<String> getWeeklyMonthlyCosts(@PathVariable String username, @PathVariable String type) {
        try {
            // Generate the key based on username and type
            String key = "users/" + username + "/" + type + "_costs.json";

            // Fetch data from S3
            byte[] fileData = s3Service.downloadFile(key);
            String jsonData = new String(fileData, StandardCharsets.UTF_8);

            return ResponseEntity.ok(jsonData);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body("No cost data found for " + username);
        }
    }

    @DeleteMapping("/{username}/{type}")
    public ResponseEntity<String> deleteWeeklyMonthlyCosts(@PathVariable String username, @PathVariable String type) {
        try {
            // Generate key to delete
            String key = "users/" + username + "/" + type + "_costs.json";

            // Delete file from S3
            s3Service.deleteFile(key);

            return ResponseEntity.ok("Deleted " + type + " costs for " + username);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error deleting data: " + e.getMessage());
        }
    }
}
