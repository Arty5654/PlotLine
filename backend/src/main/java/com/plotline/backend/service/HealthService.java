package com.plotline.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.HealthEntry;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Object;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;

import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class HealthService {

    private final S3Client s3Client;
    private final String BUCKET_NAME = "plotline-database-bucket";
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final UserProfileService userProfileService;

    public HealthService(S3Client s3Client, UserProfileService userProfileService) {
        this.userProfileService = userProfileService;
        this.s3Client = s3Client;
    }

    // Helper function to construct the S3 path for weekly health entries
    private String getWeeklyEntriesS3Path(String username, String sundayDateString) {
        return "users/" + username + "/health-entries/" + sundayDateString + "/entries.json";
    }

    // Helper function to construct the S3 prefix for all health entries of a user
    private String getUserHealthEntriesPrefix(String username) {
        return "users/" + username + "/health-entries/";
    }

    // Method to retrieve health entries for a specific week
    public List<HealthEntry> getHealthEntriesForWeek(String username, String sundayDateString) throws IOException {
        try {
            String s3Path = getWeeklyEntriesS3Path(username, sundayDateString);

            // Fetch the health entries from S3
            GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(s3Path)
                    .build();

            ResponseInputStream<GetObjectResponse> response = s3Client.getObject(getObjectRequest);

            // Parse the JSON into a list of health entries
            return Arrays.asList(objectMapper.readValue(response, HealthEntry[].class));
        } catch (NoSuchKeyException e) {
            // If no entries exist for this week, return an empty list
            return new ArrayList<>();
        } catch (Exception e) {
            e.printStackTrace();
            throw new IOException("Error retrieving health entries", e);
        }
    }

    // Method to save health entries for a specific week
    public boolean saveHealthEntries(String username, String sundayDateString, List<HealthEntry> entries) throws IOException {
        try {
            // Set or update timestamps for all entries
            String currentDate = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());
            
            for (HealthEntry entry : entries) {
                // Ensure the username is correct
                entry.setUsername(username);
                
                // Set updated timestamp
                entry.setUpdatedAt(currentDate);
                
                // If no created timestamp, set it
                if (entry.getCreatedAt() == null) {
                    entry.setCreatedAt(currentDate);
                }
                
                // If no ID, generate one
                if (entry.getId() == null) {
                    entry.setId(UUID.randomUUID().toString());
                }

                if (entry.getHoursSlept() >= 8) {
                    userProfileService.incrementTrophy(entry.getUsername(), "sleep-goal", 1);
                }
            }

            // Serialize the list of entries to JSON
            String jsonString = objectMapper.writeValueAsString(entries);

            // Get the S3 path
            String s3Path = getWeeklyEntriesS3Path(username, sundayDateString);

            // Upload to S3
            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(s3Path)
                    .build();
            s3Client.putObject(putObjectRequest, RequestBody.fromString(jsonString));

            return true;
        } catch (Exception e) {
            e.printStackTrace();
            throw new IOException("Error saving health entries", e);
        }
    }

    // Method to create a new health entry
    public String createHealthEntry(HealthEntry healthEntry) throws IOException {
        if (healthEntry.getUsername() == null || healthEntry.getUsername().isEmpty()) {
            throw new IllegalArgumentException("Username is required");
        }

        if (healthEntry.getDate() == null) {
            throw new IllegalArgumentException("Date is required");
        }

        // Generate ID if not provided
        if (healthEntry.getId() == null) {
            healthEntry.setId(UUID.randomUUID().toString());
        }

        // Get the Sunday date string for the week containing this entry
        SimpleDateFormat formatter = new SimpleDateFormat("MMddyyyy");
        Calendar calendar = Calendar.getInstance();
        calendar.setTime(healthEntry.getDate());
        
        // Set to the beginning of the week (Sunday)
        calendar.set(Calendar.DAY_OF_WEEK, Calendar.SUNDAY);
        String sundayDateString = formatter.format(calendar.getTime());

        // Try to load existing entries for this week
        List<HealthEntry> weekEntries;
        try {
            weekEntries = getHealthEntriesForWeek(healthEntry.getUsername(), sundayDateString);
        } catch (IOException e) {
            weekEntries = new ArrayList<>();
        }

        // Set timestamps
        String currentDateTime = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());
        healthEntry.setCreatedAt(currentDateTime);
        healthEntry.setUpdatedAt(currentDateTime);

        // Remove any existing entry for the same date
        weekEntries.removeIf(entry -> isSameDay(entry.getDate(), healthEntry.getDate()));
        
        // Add the new entry
        weekEntries.add(healthEntry);

        //trophy for logging health entry
        userProfileService.incrementTrophy(healthEntry.getUsername(), "sleep-tracker", 1);

        if (healthEntry.getHoursSlept() >= 8) {
            userProfileService.incrementTrophy(healthEntry.getUsername(), "sleep-goal", 1);
        }

        // Save the updated list
        saveHealthEntries(healthEntry.getUsername(), sundayDateString, weekEntries);

        return healthEntry.getId();
    }

    // Helper method to check if two dates represent the same day
    private boolean isSameDay(Date date1, Date date2) {
        Calendar cal1 = Calendar.getInstance();
        Calendar cal2 = Calendar.getInstance();
        cal1.setTime(date1);
        cal2.setTime(date2);
        return cal1.get(Calendar.YEAR) == cal2.get(Calendar.YEAR) &&
               cal1.get(Calendar.DAY_OF_YEAR) == cal2.get(Calendar.DAY_OF_YEAR);
    }

    // Method to delete a health entry
    public boolean deleteHealthEntry(String username, String entryId) throws IOException {
        // List all health entry files for this user
        String prefix = getUserHealthEntriesPrefix(username);
        ListObjectsV2Request listObjectsRequest = ListObjectsV2Request.builder()
                .bucket(BUCKET_NAME)
                .prefix(prefix)
                .build();

        var objectSummaries = s3Client.listObjectsV2(listObjectsRequest).contents();
        
        // Check each weekly entries file for the entry with the specified ID
        for (S3Object object : objectSummaries) {
            String key = object.key();
            
            // Skip if this isn't an entries.json file
            if (!key.endsWith("entries.json")) {
                continue;
            }
            
            // Get the object from S3
            GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(key)
                    .build();
                    
            try {
                ResponseInputStream<GetObjectResponse> response = s3Client.getObject(getObjectRequest);
                List<HealthEntry> entries = Arrays.asList(objectMapper.readValue(response, HealthEntry[].class));
                
                // Check if the entry with the specified ID exists in this file
                Optional<HealthEntry> entryToDelete = entries.stream()
                        .filter(entry -> entry.getId().equals(entryId))
                        .findFirst();
                        
                if (entryToDelete.isPresent()) {
                    // Remove the entry
                    List<HealthEntry> updatedEntries = entries.stream()
                            .filter(entry -> !entry.getId().equals(entryId))
                            .collect(Collectors.toList());
                            
                    // Save the updated file
                    String jsonString = objectMapper.writeValueAsString(updatedEntries);
                    PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                            .bucket(BUCKET_NAME)
                            .key(key)
                            .build();
                    s3Client.putObject(putObjectRequest, RequestBody.fromString(jsonString));
                    
                    return true;
                }
            } catch (Exception e) {
                // Log error and continue checking other files
                System.err.println("Error processing file " + key + ": " + e.getMessage());
            }
        }
        
        // Entry not found
        return false;
    }

    // Method to get all health entries for a user
    public List<HealthEntry> getAllHealthEntries(String username) throws IOException {
        List<HealthEntry> allEntries = new ArrayList<>();
        
        // List all health entry files for this user
        String prefix = getUserHealthEntriesPrefix(username);
        ListObjectsV2Request listObjectsRequest = ListObjectsV2Request.builder()
                .bucket(BUCKET_NAME)
                .prefix(prefix)
                .build();

        var objectSummaries = s3Client.listObjectsV2(listObjectsRequest).contents();
        
        // Collect entries from all files
        for (S3Object object : objectSummaries) {
            String key = object.key();
            
            // Skip if this isn't an entries.json file
            if (!key.endsWith("entries.json")) {
                continue;
            }
            
            try {
                // Get the object from S3
                GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                        .bucket(BUCKET_NAME)
                        .key(key)
                        .build();
                        
                ResponseInputStream<GetObjectResponse> response = s3Client.getObject(getObjectRequest);
                List<HealthEntry> entries = Arrays.asList(objectMapper.readValue(response, HealthEntry[].class));
                
                allEntries.addAll(entries);
            } catch (Exception e) {
                System.err.println("Error processing file " + key + ": " + e.getMessage());
            }
        }
        
        // Sort entries by date (newest first)
        allEntries.sort((e1, e2) -> e2.getDate().compareTo(e1.getDate()));
        
        return allEntries;
    }

    // Method to generate insights based on health entries
    public Object generateHealthInsights(String username) throws IOException {
        // Get all entries for the user
        List<HealthEntry> allEntries = getAllHealthEntries(username);
        
        if (allEntries.isEmpty()) {
            return Map.of("message", "Not enough data to generate insights");
        }
        
        // Calculate average sleep time
        double avgSleepHours = allEntries.stream()
                .mapToInt(HealthEntry::getHoursSlept)
                .average()
                .orElse(0);
                
        // Count occurrences of each mood
        Map<String, Integer> moodCounts = new HashMap<>();
        for (HealthEntry entry : allEntries) {
            String mood = entry.getMood();
            moodCounts.put(mood, moodCounts.getOrDefault(mood, 0) + 1);
        }
        
        // Find most common mood
        String mostCommonMood = "";
        int maxCount = 0;
        for (Map.Entry<String, Integer> entry : moodCounts.entrySet()) {
            if (entry.getValue() > maxCount) {
                maxCount = entry.getValue();
                mostCommonMood = entry.getKey();
            }
        }
        
        // Create insights object
        Map<String, Object> insights = new HashMap<>();
        insights.put("totalEntries", allEntries.size());
        insights.put("averageSleepHours", avgSleepHours);
        insights.put("moodDistribution", moodCounts);
        insights.put("mostCommonMood", mostCommonMood);
        
        // Add data for last 7 days if available
        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.DAY_OF_YEAR, -7);
        Date sevenDaysAgo = cal.getTime();
        
        List<HealthEntry> recentEntries = allEntries.stream()
                .filter(entry -> entry.getDate().after(sevenDaysAgo))
                .collect(Collectors.toList());
                
        insights.put("entriesLastSevenDays", recentEntries.size());
        
        return insights;
    }
}