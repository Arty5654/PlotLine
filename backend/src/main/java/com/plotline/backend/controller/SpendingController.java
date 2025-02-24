package com.plotline.backend.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.SpendingRequest;
import com.plotline.backend.service.S3Service;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;


import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;

@RestController
@RequestMapping("/api/spending")
public class SpendingController {

    private static final Logger logger = LoggerFactory.getLogger(SpendingController.class);

    @Autowired
    private S3Service s3Service;

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final String S3_BUCKET_PATH = "users/%s/spending/%s.json"; // Path pattern

    // Save Spending Data
    @PostMapping
  public ResponseEntity<String> saveSpending(@RequestBody SpendingRequest request) {
      try {
          logger.info("Received Spending Request: {}", objectMapper.writeValueAsString(request));

          if (request.getStartDate() == null || request.getEndDate() == null || 
              request.getStartDate().isEmpty() || request.getEndDate().isEmpty()) {
              return ResponseEntity.status(HttpStatus.BAD_REQUEST).body("Start and end date cannot be null or empty.");
          }

          // Ensure the date range is valid
          if (request.getStartDate().compareTo(request.getEndDate()) > 0) {
              return ResponseEntity.status(HttpStatus.BAD_REQUEST).body("Start date cannot be after end date.");
          }

          // Convert request to JSON string
          String jsonData = objectMapper.writeValueAsString(request);
          ByteArrayInputStream inputStream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));

          // Use a file key format that includes both start and end dates
          String key = String.format("users/%s/spending/%s_to_%s.json", request.getUsername(), request.getStartDate(), request.getEndDate());

          logger.info("📝 Saving spending for {} to {}", request.getStartDate(), request.getEndDate());
          // Upload to S3
          s3Service.uploadFile(key, inputStream, jsonData.length());

          return ResponseEntity.ok("Spending data saved successfully.");
      } catch (Exception e) {
          return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error saving spending: " + e.getMessage());
      }
  }


    // Get Spending Data for a Specific Date
    @GetMapping("/{username}/{startDate}/{endDate}")
    public ResponseEntity<String> getSpending(@PathVariable String username, @PathVariable String startDate, @PathVariable String endDate) {
        try {
            String key = String.format("users/%s/spending/%s_to_%s.json", username, startDate, endDate);
            byte[] fileData = s3Service.downloadFile(key);
            String jsonData = new String(fileData, StandardCharsets.UTF_8);

            return ResponseEntity.ok(jsonData);
        } catch (Exception e) {
            // If no data found, return an empty JSON with the correct structure
            String emptyJson = "{ \"username\": \"" + username + "\", \"startDate\": \"" + startDate + "\", \"endDate\": \"" + endDate + "\", \"spending\": {} }";
            return ResponseEntity.ok(emptyJson);
        }
    }


    // Delete Spending Data for a Specific Date
    @DeleteMapping("/{username}/{startDate}/{endDate}")
    public ResponseEntity<String> deleteSpending(@PathVariable String username, @PathVariable String startDate, @PathVariable String endDate) {
        try {
            String key = String.format("users/%s/spending/%s_to_%s.json", username, startDate, endDate);
            logger.info("🔍 Attempting to delete file with key: {}", key);
            logger.info("🗑 Deleting spending for {} to {}", startDate, endDate);
            s3Service.deleteFile(key);
            return ResponseEntity.ok("Spending data deleted successfully.");
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error deleting spending: " + e.getMessage());
        }
    }

}
