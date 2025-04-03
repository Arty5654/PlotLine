package com.plotline.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.SleepSchedule;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;

import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.UUID;

@Service
public class SleepScheduleService {

    private final S3Client s3Client;
    private final String BUCKET_NAME = "plotline-database-bucket";
    private final ObjectMapper objectMapper = new ObjectMapper();

    public SleepScheduleService(S3Client s3Client) {
        this.s3Client = s3Client;
    }

    // Helper function to construct the S3 path for the sleep schedule
    private String getSleepScheduleS3Path(String username) {
        return "users/" + username + "/health-entries/sleep_schedule.json";
    }

    // Method to get sleep schedule for a user
    public SleepSchedule getSleepSchedule(String username) throws IOException {
        try {
            String s3Path = getSleepScheduleS3Path(username);

            // Fetch the sleep schedule from S3
            GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(s3Path)
                    .build();

            ResponseInputStream<GetObjectResponse> response = s3Client.getObject(getObjectRequest);

            // Parse the JSON into a SleepSchedule object
            return objectMapper.readValue(response, SleepSchedule.class);
        } catch (NoSuchKeyException e) {
            // If no schedule exists yet, create and return a default one
            return createDefaultSleepSchedule(username);
        } catch (Exception e) {
            e.printStackTrace();
            throw new IOException("Error retrieving sleep schedule", e);
        }
    }

    // Method to save sleep schedule for a user
    public boolean saveSleepSchedule(SleepSchedule sleepSchedule) throws IOException {
        try {
            if (sleepSchedule.getUsername() == null || sleepSchedule.getUsername().isEmpty()) {
                throw new IllegalArgumentException("Username is required");
            }

            // Generate ID if not provided
            if (sleepSchedule.getId() == null) {
                sleepSchedule.setId(UUID.randomUUID().toString());
            }

            // Set timestamps
            String currentDateTime = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());
            if (sleepSchedule.getCreatedAt() == null) {
                sleepSchedule.setCreatedAt(currentDateTime);
            }
            sleepSchedule.setUpdatedAt(currentDateTime);

            // Serialize the sleep schedule to JSON
            String jsonString = objectMapper.writeValueAsString(sleepSchedule);

            // Upload to S3
            String s3Path = getSleepScheduleS3Path(sleepSchedule.getUsername());
            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(s3Path)
                    .build();
            s3Client.putObject(putObjectRequest, RequestBody.fromString(jsonString));

            return true;
        } catch (Exception e) {
            e.printStackTrace();
            throw new IOException("Error saving sleep schedule", e);
        }
    }

    // Helper method to create a default sleep schedule
    private SleepSchedule createDefaultSleepSchedule(String username) throws IOException {
        Calendar calendar = Calendar.getInstance();
        
        // Default wake up time (9:00 AM)
        Calendar wakeUpCal = Calendar.getInstance();
        wakeUpCal.set(Calendar.HOUR_OF_DAY, 9);
        wakeUpCal.set(Calendar.MINUTE, 0);
        wakeUpCal.set(Calendar.SECOND, 0);
        wakeUpCal.set(Calendar.MILLISECOND, 0);
        Date wakeUpTime = wakeUpCal.getTime();
        
        // Default sleep time (11:00 PM)
        Calendar sleepCal = Calendar.getInstance();
        sleepCal.set(Calendar.HOUR_OF_DAY, 23);
        sleepCal.set(Calendar.MINUTE, 0);
        sleepCal.set(Calendar.SECOND, 0);
        sleepCal.set(Calendar.MILLISECOND, 0);
        Date sleepTime = sleepCal.getTime();
        
        // Create a new sleep schedule
        SleepSchedule sleepSchedule = new SleepSchedule(
            UUID.randomUUID().toString(),
            username,
            wakeUpTime,
            sleepTime
        );
        
        // Set timestamps
        String currentDateTime = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());
        sleepSchedule.setCreatedAt(currentDateTime);
        sleepSchedule.setUpdatedAt(currentDateTime);
        
        // Save the default schedule
        saveSleepSchedule(sleepSchedule);
        
        return sleepSchedule;
    }
}