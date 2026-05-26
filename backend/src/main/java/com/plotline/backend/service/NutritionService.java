package com.plotline.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import java.nio.charset.StandardCharsets;
import java.util.regex.Pattern;

import static com.plotline.backend.util.UsernameUtils.normalize;

@Service
public class NutritionService {

    private final S3Client s3Client;
    private final ObjectMapper objectMapper;
    private final String bucketName = "plotline-database-bucket";
    private static final Pattern DATE_KEY_PATTERN = Pattern.compile("^\\d{4}-\\d{2}-\\d{2}$");

    public NutritionService(S3Client s3Client) {
        this.s3Client = s3Client;
        this.objectMapper = new ObjectMapper();
    }

    private String getS3Key(String username, String dateKey) {
        if (!DATE_KEY_PATTERN.matcher(dateKey).matches()) {
            throw new IllegalArgumentException("Invalid dateKey format: " + dateKey);
        }
        return "users/" + normalize(username) + "/nutrition/" + dateKey + ".json";
    }

    private String getUserDataKey(String username) {
        return "users/" + normalize(username) + "/nutrition/user-data.json";
    }

    public String getUserData(String username) throws Exception {
        String key = getUserDataKey(username);
        GetObjectRequest getRequest = GetObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .build();
        try {
            ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
            return new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);
        } catch (NoSuchKeyException e) {
            return null;
        }
    }

    public void saveUserData(String username, String json) throws Exception {
        String key = getUserDataKey(username);

        PutObjectRequest putRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .contentType("application/json")
                .build();

        s3Client.putObject(putRequest, RequestBody.fromString(json));
    }

    public String getEntry(String username, String dateKey) throws Exception {
        String key = getS3Key(username, dateKey);
        GetObjectRequest getRequest = GetObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .build();
        try {
            ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
            return new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);
        } catch (NoSuchKeyException e) {
            return null;
        }
    }

    public void saveEntry(String username, String dateKey, String entryJson) throws Exception {
        String key = getS3Key(username, dateKey);

        PutObjectRequest putRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .contentType("application/json")
                .build();

        s3Client.putObject(putRequest, RequestBody.fromString(entryJson));
    }
}
