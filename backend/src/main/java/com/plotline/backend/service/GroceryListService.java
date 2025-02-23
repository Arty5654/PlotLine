package com.plotline.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.GroceryItem;
import com.plotline.backend.dto.GroceryList;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Object;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;

import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.UUID;

@Service
public class GroceryListService {

    private final S3Client s3Client;
    private final String BUCKET_NAME = "plotline-database-bucket";

    public GroceryListService(S3Client s3Client) {
        this.s3Client = s3Client;
    }

    // Helper function to construct the S3 path for the grocery list items
    private String getS3Path(String username, String listId) {
        return "users/" + username + "/grocery_lists/" + listId + ".json";
    }

    public GroceryList getGroceryList(String username, String listId) {
        try {
            String s3Path = getS3Path(username, listId);

            // Fetch the grocery list from S3
            GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(s3Path)
                    .build();

            ResponseInputStream<GetObjectResponse> response = s3Client.getObject(getObjectRequest);

            // Parse the grocery list JSON into a GroceryList object
            return objectMapper.readValue(response, GroceryList.class);

        } catch (Exception e) {
            e.printStackTrace();
            return null;  // Return null if the list doesn't exist or an error occurs
        }
    }


    // Method to check if a grocery list already exists for the user (based on name)
    public boolean doesGroceryListExist(String username, String groceryListName) {
        // Construct the S3 key path to check for the existence of the grocery list
        String s3Path = "users/" + username + "/grocery_lists/";

        // List all objects in the grocery lists folder for the user
        ListObjectsV2Request listObjectsV2Request = ListObjectsV2Request.builder()
                .bucket(BUCKET_NAME)
                .prefix(s3Path)
                .build();
        var objectSummaries = s3Client.listObjectsV2(listObjectsV2Request).contents();

        // Check if any of the object names match the grocery list name
        for (var summary : objectSummaries) {
            if (summary.key().contains(groceryListName)) {
                return true;  // If the list name already exists, return true
            }
        }
        return false;  // If the list name does not exist, return false
    }

    // Method to create and save a grocery list to S3 in JSON format
    public String createGroceryList(GroceryList groceryList, String username) throws IOException {
        // Check if the grocery list with the same name already exists for the user
        if (doesGroceryListExist(username, groceryList.getName())) {
            throw new IllegalArgumentException("A grocery list with this name already exists.");
        }

        System.out.println("before if else" + groceryList.getId());
        String groceryListID = groceryList.getId() != null ? groceryList.getId() : UUID.randomUUID().toString();
        System.out.println("after if else" + groceryListID);

        groceryList.setId(groceryListID);

        // Set createdAt and updatedAt to the current date-time
        String currentDate = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());
        groceryList.setCreatedAt(currentDate);
        groceryList.setUpdatedAt(currentDate);

        // Serialize the GroceryList object to JSON
        ObjectMapper objectMapper = new ObjectMapper();
        String jsonString = objectMapper.writeValueAsString(groceryList);

        // Use a UUID for the file name in S3 to ensure uniqueness
        String s3Key = "users/" + username + "/grocery_lists/" + groceryListID + ".json";

        // Create a PutObjectRequest with the bucket name, S3 key, and content
        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(BUCKET_NAME)
                .key(s3Key)
                .build();
        s3Client.putObject(putObjectRequest, RequestBody.fromBytes(jsonString.getBytes()));

        return s3Key;  // Return the key of the uploaded object (i.e., the S3 file path)
    }

    // Fetch all grocery lists for a specific user from S3
    public List<GroceryList> getGroceryListsForUser(String username) throws IOException {
        List<GroceryList> groceryLists = new ArrayList<>();

        // Construct the S3 key path to list all grocery lists for the user
        String s3Path = "users/" + username + "/grocery_lists/";

        // List all objects in the grocery lists folder for the user
        ListObjectsV2Request listObjectsV2Request = ListObjectsV2Request.builder()
                .bucket(BUCKET_NAME)
                .prefix(s3Path)
                .build();

        var objectSummaries = s3Client.listObjectsV2(listObjectsV2Request).contents();

        // For each grocery list file, read and parse the content
        for (S3Object object : objectSummaries) {
            String key = object.key();
            var s3Object = s3Client.getObject(b -> b.bucket(BUCKET_NAME).key(key));
            var objectContent = new String(s3Object.readAllBytes());  // Read the content as a String

            // Convert the JSON content to a GroceryList object
            ObjectMapper objectMapper = new ObjectMapper();
            GroceryList groceryList = objectMapper.readValue(objectContent, GroceryList.class);
            groceryLists.add(groceryList);
        }

        return groceryLists;
    }

    private ObjectMapper objectMapper = new ObjectMapper();

    // Fetch grocery list items from S3
    public List<GroceryItem> getItems(String username, String listId) {
        try {
            // Log the username and listId to ensure they are being passed correctly
            System.out.println("Fetching items for listId: " + listId + " and username: " + username);

            // Construct the S3 path using the username and listId
            String s3Path = getS3Path(username, listId);

            // Log the constructed S3 path
            System.out.println("S3 path for the grocery list: " + s3Path);

            // Get the object from S3
            GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(s3Path)
                    .build();

            // Download the file from S3
            ResponseInputStream<GetObjectResponse> response = s3Client.getObject(getObjectRequest);

            // Log the success of the download (or size of the file)
            System.out.println("Successfully retrieved the grocery list from S3");

            // Deserialize the grocery list JSON into an object
            GroceryList groceryList = objectMapper.readValue(response, GroceryList.class);

            // Log the items in the grocery list
            System.out.println("Items in the grocery list: " + groceryList.getItems());

            return groceryList.getItems();  // Return the list of items

        } catch (Exception e) {
            // Log the error if there is any issue
            System.out.println("Error while fetching items: " + e.getMessage());
            e.printStackTrace();
            return new ArrayList<>();  // Return an empty list if an error occurs
        }
    }

    // Add an item to the grocery list in S3
    public boolean addItem(String username, String listId, GroceryItem item) {
        try {
            // Log the item being added
            System.out.println("Adding item to the list: " + item);

            // Get the existing grocery list from S3
            GroceryList groceryList = getGroceryList(username, listId);

            if (groceryList == null) {
                System.out.println("Grocery list not found.");
                return false;
            }

            // Log the current items in the grocery list before adding the new item
            System.out.println("Items before adding new item:");
            System.out.println(groceryList.getItems());

            // Add the new item to the existing items array
            groceryList.getItems().add(item);

            // Log the updated list of items
            System.out.println("Items after adding new item:");
            System.out.println(groceryList.getItems());

            // Update the updatedAt timestamp to the current date-time
            String currentDate = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());
            groceryList.setUpdatedAt(currentDate);  // Update the 'updatedAt' field

            // Log the updated grocery list with the new 'updatedAt'
            System.out.println("Updated grocery list with updatedAt: " + groceryList.getUpdatedAt());

            // Serialize the entire grocery list back to JSON (not just the items array)
            String updatedListJson = objectMapper.writeValueAsString(groceryList);

            // Log the updated JSON
            System.out.println("Updated list JSON:");
            System.out.println(updatedListJson);

            // Get the S3 path to store the updated grocery list
            String s3Path = getS3Path(username, listId);

            // Upload the updated grocery list back to S3
            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(s3Path)
                    .build();
            s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedListJson));

            return true;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }


    // Delete an item from the grocery list in S3
    public boolean deleteItem(String username, String listId, String itemId) {
        try {
            // Fetch the existing grocery list from S3
            GroceryList groceryList = getGroceryList(username, listId);

            if (groceryList == null) {
                System.out.println("Grocery list not found.");
                return false;
            }

            // Log the current items in the grocery list before removing the item
            System.out.println("Items before deleting:");
            System.out.println(groceryList.getItems());

            // Remove the item from the list based on its name (itemId is the name here)
            boolean itemRemoved = groceryList.getItems().removeIf(item -> item.getName().equals(itemId));

            if (itemRemoved) {
                // Log the updated list of items
                System.out.println("Items after deleting the item:");
                System.out.println(groceryList.getItems());

                // Update the updatedAt timestamp to the current date-time
                String currentDate = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());
                groceryList.setUpdatedAt(currentDate);  // Update the 'updatedAt' field

                // Serialize the entire grocery list back to JSON (not just the items array)
                String updatedListJson = objectMapper.writeValueAsString(groceryList);

                // Log the updated JSON
                System.out.println("Updated list JSON after item deletion:");
                System.out.println(updatedListJson);

                // Get the S3 path to store the updated grocery list
                String s3Path = getS3Path(username, listId);

                // Upload the updated grocery list back to S3
                PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                        .bucket(BUCKET_NAME)
                        .key(s3Path)
                        .build();
                s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedListJson));

                return true;
            } else {
                System.out.println("Item not found in the grocery list.");
                return false;
            }

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }
}