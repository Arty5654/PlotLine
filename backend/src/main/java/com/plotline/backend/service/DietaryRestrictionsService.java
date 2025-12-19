package com.plotline.backend.service;

import com.plotline.backend.dto.DietaryRestrictions;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import java.io.IOException;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class DietaryRestrictionsService {

    private final S3Client s3Client;
    private final String BUCKET_NAME = "plotline-database-bucket";

    // Path to the dietary restrictions JSON file in S3
    private static final String DIETARY_RESTRICTIONS_PATH = "users/%s/grocery/dietary_restrictions.json";

    // ObjectMapper to handle JSON (serialization and deserialization)
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Autowired
    public DietaryRestrictionsService(S3Client s3Client) {
        this.s3Client = s3Client;
    }

    private String normalize(String username) {
        return username == null ? "" : username.trim().toLowerCase();
    }

    // Get dietary restrictions for the given user
    public DietaryRestrictions getDietaryRestrictions(String username) {
        try {
            String key = String.format(DIETARY_RESTRICTIONS_PATH, normalize(username));

            // Build the GetObjectRequest to retrieve the dietary restrictions JSON file
            GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(key)
                    .build();

            // Get the S3 object
            ResponseInputStream<GetObjectResponse> response = s3Client.getObject(getObjectRequest);

            // Deserialize the S3 response content into a DietaryRestrictions object
            return objectMapper.readValue(response, DietaryRestrictions.class);

        } catch (IOException e) {
            throw new RuntimeException("Error fetching dietary restrictions for user: " + username, e);
        }
    }

    // Update dietary restrictions for the given user
    public void updateDietaryRestrictions(String username, DietaryRestrictions dietaryRestrictions) {
        try {
            String key = String.format(DIETARY_RESTRICTIONS_PATH, normalize(username));

            // Convert the DietaryRestrictions object to JSON string
            String dietaryRestrictionsJson = objectMapper.writeValueAsString(dietaryRestrictions);

            // Build the PutObjectRequest to upload the updated dietary restrictions JSON file to S3
            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(key)
                    .build();

            // Upload the updated JSON content to S3
            s3Client.putObject(putObjectRequest, RequestBody.fromString(dietaryRestrictionsJson));

        } catch (IOException e) {
            throw new RuntimeException("Backend Error updating dietary restrictions for user: " + username, e);
        }
    }
}
