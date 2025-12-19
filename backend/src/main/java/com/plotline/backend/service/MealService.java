package com.plotline.backend.service;

import software.amazon.awssdk.services.s3.S3Client;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.GroceryList;

import io.jsonwebtoken.io.IOException;

import org.springframework.stereotype.Service;

import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
public class MealService {

    private final S3Client s3Client;
    private final String BUCKET_NAME = "plotline-database-bucket";  // Replace with your actual bucket name

    // Optionally, add UserProfileService if needed
    // private final UserProfileService userProfileService;

    private final GroceryListService groceryListService;

    public MealService(S3Client s3Client, GroceryListService groceryListService) {
        this.s3Client = s3Client;
        this.groceryListService = groceryListService;
        // Initialize UserProfileService if needed
        // this.userProfileService = userProfileService;
    }

    private String normalize(String username) {
        return username == null ? "" : username.trim().toLowerCase();
    }

    // Helper function to construct the S3 path for the meal
    private String getS3Path(String username, String mealID) {
        String normUser = normalize(username);
        return "users/" + normUser + "/meals/" + mealID.toUpperCase() + ".json";
    }

    // Method to list all meal files for a user and fetch meal data
    public List<Map<String, Object>> getAllMealsFromS3(String username) throws IOException, java.io.IOException {
        String normUser = normalize(username);
        // Construct the path to the user's meal folder in S3
        String prefix = "users/" + normUser + "/meals/";

        // List all objects under the user's meals folder
        ListObjectsV2Request listObjectsRequest = ListObjectsV2Request.builder()
                .bucket(BUCKET_NAME)
                .prefix(prefix)
                .build();

        ListObjectsV2Response listObjectsResponse = s3Client.listObjectsV2(listObjectsRequest);

        List<Map<String, Object>> meals = new ArrayList<>();

        // Iterate over each object in the user's meal folder
        for (var s3Object : listObjectsResponse.contents()) {
            String mealID = s3Object.key().substring(s3Object.key().lastIndexOf("/") + 1, s3Object.key().lastIndexOf("."));

            // Fetch each meal's JSON data from S3
            Map<String, Object> meal = getMealFromS3(normUser, mealID);
            meals.add(meal);
        }

        return meals;
    }

    // Method to fetch meal from S3 using mealID and username
    public Map<String, Object> getMealFromS3(String username, String mealID) throws IOException, java.io.IOException {
        String normUser = normalize(username);
        // Construct the S3 path for the meal
        String fileName = "users/" + normUser + "/meals/" + mealID + ".json";

        // Get the object from S3
        GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                .bucket(BUCKET_NAME)
                .key(fileName)
                .build();

        // Fetch the object from S3
        ResponseInputStream<?> objectData = s3Client.getObject(getObjectRequest);

        // Convert the input stream to a string
        String mealJson = new String(objectData.readAllBytes(), StandardCharsets.UTF_8);

        // Convert the JSON string to a Map (you can use a DTO instead if desired)
        ObjectMapper objectMapper = new ObjectMapper();
        return objectMapper.readValue(mealJson, Map.class);
    }

    // Method to create and save the meal recipe in S3
    public void createMeal(String username, String listID, String mealRecipe, List<Map<String, Object>> groceryItems) {
        try {
            String normUser = normalize(username);
            // Parse mealRecipe into a structured JSON format
            ObjectMapper objectMapper = new ObjectMapper();
            Map<String, Object> meal = objectMapper.readValue(mealRecipe, Map.class);

            // Generate a unique file name for the meal using UUID
            String mealID = UUID.randomUUID().toString().toUpperCase();
            String fileName = getS3Path(normUser, mealID);

            meal.put("mealID", mealID);
            meal.put("listID", listID);

            // Convert meal entry to JSON string
            String mealJson = objectMapper.writeValueAsString(meal);

            // Prepare the S3 put request
            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(fileName)
                    .build();

            // Save the meal JSON to S3
            s3Client.putObject(putObjectRequest, RequestBody.fromString(mealJson));

            // add the meal ID to the respective grocery list
            GroceryList groceryList = groceryListService.getGroceryList(normUser, listID);

            // Update the grocery list with meal information
            groceryList.setMealID(mealID);
            groceryList.setMealName(meal.get("mealName").toString());

            // Now convert the updated grocery list to JSON
            String groceryListJson = objectMapper.writeValueAsString(groceryList);

            // save the grocery list to S3
            String groceryListFileName = "users/" + normUser + "/grocery/lists/" + listID + ".json";
            PutObjectRequest groceryListPutObjectRequest = PutObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(groceryListFileName)
                    .build();

            // Save the grocery list JSON to S3
            s3Client.putObject(groceryListPutObjectRequest, RequestBody.fromString(groceryListJson));

        } catch (Exception e) {
            // Log the error and handle it properly
            e.printStackTrace();
            throw new RuntimeException("Error creating meal: " + e.getMessage());
        }
    }
}
