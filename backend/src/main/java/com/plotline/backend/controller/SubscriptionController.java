package com.plotline.backend.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.SubscriptionRequest;
import com.plotline.backend.service.S3Service;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.TimeZone;

@RestController
@RequestMapping("/api/subscriptions")
public class SubscriptionController {

    @Autowired
    private S3Service s3Service;

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final String S3_BUCKET_PATH = "users/%s/subscriptions.json"; // Storage path

    @PostMapping
    public ResponseEntity<String> saveSubscriptions(@RequestBody SubscriptionRequest request) {
        try {
            // Convert the entire 'request' to JSON
            String jsonData = objectMapper.writeValueAsString(request);

            // Convert JSON string to InputStream
            ByteArrayInputStream inputStream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));

            // Generate S3 key
            String key = String.format(S3_BUCKET_PATH, request.getUsername());

            // Upload to S3
            s3Service.uploadFile(key, inputStream, jsonData.length());

            return ResponseEntity.ok("Subscriptions saved successfully.");
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                                .body("Error saving subscriptions: " + e.getMessage());
        }
    }

    @GetMapping("/{username}")
    public ResponseEntity<Object> getSubscriptions(@PathVariable String username) {
        try {
            String key = String.format(S3_BUCKET_PATH, username);
            byte[] data = s3Service.downloadFile(key);
            String json = new String(data, StandardCharsets.UTF_8);

            SubscriptionRequest request = objectMapper.readValue(json, SubscriptionRequest.class);

            // Convert UTC to EST before sending response
            for (SubscriptionRequest.SubscriptionItem item : request.getSubscriptions().values()) {
                item.setDueDate(convertUtcToEst(item.getDueDate()));
            }
          
            return ResponseEntity.ok(request);  // Returns the same structure
        } catch (Exception e) {
            return ResponseEntity.ok("{}"); // Return empty JSON if none
        }
    }

    private Date convertUtcToEst(Date utcDate) {
      TimeZone estTimeZone = TimeZone.getTimeZone("America/New_York");
      SimpleDateFormat estFormat = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
      estFormat.setTimeZone(estTimeZone);
      try {
          String formattedDate = estFormat.format(utcDate);
          return estFormat.parse(formattedDate);
      } catch (Exception e) {
          return utcDate;  // Return the original if conversion fails
      }
    }


    // Delete Subscription
    @DeleteMapping("/{username}/{subscriptionName}")
    public ResponseEntity<String> deleteSubscription(@PathVariable String username, @PathVariable String subscriptionName) {
        try {
            String key = String.format(S3_BUCKET_PATH, username);
            byte[] data = s3Service.downloadFile(key);
            List<SubscriptionRequest.SubscriptionItem> subscriptions = objectMapper.readValue(data, List.class);

            // Remove the subscription with the matching name
            subscriptions.removeIf(sub -> sub.getName().equalsIgnoreCase(subscriptionName));

            // Save the updated list
            String jsonData = objectMapper.writeValueAsString(subscriptions);
            ByteArrayInputStream inputStream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));
            s3Service.uploadFile(key, inputStream, jsonData.length());

            return ResponseEntity.ok("Subscription deleted successfully.");
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error deleting subscription: " + e.getMessage());
        }
    }
}
