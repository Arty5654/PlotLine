package com.plotline.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.plotline.backend.dto.GroceryItem;
import com.plotline.backend.dto.GroceryList;
import com.twilio.rest.chat.v1.service.User;

import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Object;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
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

    private final UserProfileService userProfileService;

    public GroceryListService(S3Client s3Client, UserProfileService userProfileService) {
        this.s3Client = s3Client;
        this.userProfileService = userProfileService;
    }

    // Helper function to construct the S3 path for the grocery list items
    private String getS3Path(String username, String listId) {
        return "users/" + username + "/grocery/lists/" + listId.toUpperCase() + ".json";
    }

    // Method to fetch a grocery list from S3
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
        String s3Path = "users/" + username + "/grocery/lists/";

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

        String groceryListID = groceryList.getId() != null ? groceryList.getId() : UUID.randomUUID().toString().toUpperCase();

        groceryList.setId(groceryListID);

        // Set createdAt and updatedAt to the current date-time
        String currentDate = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());
        groceryList.setCreatedAt(currentDate);
        groceryList.setUpdatedAt(currentDate);

        // Serialize the GroceryList object to JSON
        ObjectMapper objectMapper = new ObjectMapper();
        String jsonString = objectMapper.writeValueAsString(groceryList);

        // Use the new path structure
        String s3Key = "users/" + username + "/grocery/lists/" + groceryListID + ".json";

        // Create a PutObjectRequest with the bucket name, S3 key, and content
        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(BUCKET_NAME)
                .key(s3Key)
                .build();
        s3Client.putObject(putObjectRequest, RequestBody.fromBytes(jsonString.getBytes()));

        // Update the user's trophy progress for creating a grocery list
        userProfileService.incrementTrophy(username, "grocery-lists", 1);

        return groceryListID;  // Return the key of the uploaded object (i.e., the S3 file path)
    }

    // Fetch all grocery lists for a specific user from S3
    public List<GroceryList> getGroceryListsForUser(String username) throws IOException {
        List<GroceryList> groceryLists = new ArrayList<>();

        // Construct the S3 key path to list all grocery lists for the user
        String s3Path = "users/" + username + "/grocery/lists/";

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

    public List<GroceryItem> getItems(String username, String listId) {
    try {
        // Construct the exact S3 key path
        String s3Path = getS3Path(username, listId);

        // Get the grocery list from S3
        GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                .bucket(BUCKET_NAME)
                .key(s3Path)
                .build();

        ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
        String jsonContent = objectBytes.asUtf8String();

        // Parse the JSON to get the grocery list
        ObjectMapper mapper = new ObjectMapper();
        GroceryList groceryList = mapper.readValue(jsonContent, GroceryList.class);

        // Return the items from the grocery list
        return groceryList.getItems();
    } catch (Exception e) {
        e.printStackTrace();
        return new ArrayList<>(); // Return empty list on error
    }
}

    // Add an item to the grocery list in S3
    public boolean addItem(String username, String listId, GroceryItem item) {
        try {
            // Get the existing grocery list from S3
            GroceryList groceryList = getGroceryList(username, listId);

            if (groceryList == null) {
                return false;
            }

            // Add the new item to the existing items array
            groceryList.getItems().add(item);

            // Update the updatedAt timestamp to the current date-time
            String currentDate = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());
            groceryList.setUpdatedAt(currentDate);  // Update the 'updatedAt' field

            // Serialize the entire grocery list back to JSON (not just the items array)
            String updatedListJson = objectMapper.writeValueAsString(groceryList);

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
                return false;
            }

            // Remove the item from the list based on its id
            boolean itemRemoved = groceryList.getItems().removeIf(item -> item.getId().equals(itemId));

            if (itemRemoved) {
                // Update the updatedAt timestamp to the current date-time
                String currentDate = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());
                groceryList.setUpdatedAt(currentDate);  // Update the 'updatedAt' field

                // Serialize the entire grocery list back to JSON (not just the items array)
                String updatedListJson = objectMapper.writeValueAsString(groceryList);

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
                return false;
            }

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    // Backend function to toggle the checked status of a grocery item
    public boolean toggleChecked(String username, String listId, String itemId) {
        try {
            // Fetch the grocery list from S3
            GroceryList groceryList = getGroceryList(username, listId);

            if (groceryList == null) {
                return false;
            }

            // Find the item by ID and toggle its 'checked' state
            java.util.Optional<GroceryItem> itemOpt = groceryList.getItems().stream()
                    .filter(item -> item.getId().toString().equals(itemId))
                    .findFirst();

            if (itemOpt.isPresent()) {
                GroceryItem item = itemOpt.get();
                item.setChecked(!item.isChecked());  // Toggle the checked status
                groceryList.setUpdatedAt(new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date()));  // Update the timestamp

                // Serialize the updated grocery list back to JSON
                String s3Path = getS3Path(username, listId);
                String updatedListJson = objectMapper.writeValueAsString(groceryList);

                // Upload the updated list back to S3
                PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                        .bucket(BUCKET_NAME)
                        .key(s3Path)
                        .build();
                s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedListJson));

                return true;
            } else {
                return false;
            }

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    // Method to update the item order in the grocery list
    public boolean updateItemOrder(String username, String listId, List<GroceryItem> reorderedItems) throws IOException {
        try {
            // Fetch the grocery list from S3
            GroceryList groceryList = getGroceryList(username, listId);

            if (groceryList == null) {
                return false;
            }

            // Update the items list with the new order
            groceryList.setItems(reorderedItems);

            // Update the 'updatedAt' timestamp
            String currentDate = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());
            groceryList.setUpdatedAt(currentDate);

            // Serialize the updated grocery list back to JSON
            String updatedListJson = objectMapper.writeValueAsString(groceryList);

            // Upload the updated grocery list back to S3
            String s3Path = getS3Path(username, listId);
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

    // Method to update an items information in the grocery list
    public boolean updateItemDetails(String username, String listId, GroceryItem updatedItem) {
        try {
            // Fetch the grocery list from S3
            GroceryList groceryList = getGroceryList(username, listId);

            if (groceryList == null) {
                return false;
            }

            // Find the item by ID and update its information
            for (GroceryItem item : groceryList.getItems()) {
                if (item.getId().equals(updatedItem.getId())) {
                    item.setName(updatedItem.getName());
                    item.setQuantity(updatedItem.getQuantity());
                    item.setChecked(updatedItem.isChecked());
                    item.setPrice(updatedItem.getPrice());
                    item.setStore(updatedItem.getStore());
                    item.setNotes(updatedItem.getNotes());
                    break;
                }
            }

            // Update the 'updatedAt' timestamp
            String currentDate = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());
            groceryList.setUpdatedAt(currentDate);

            // Serialize the updated grocery list back to JSON
            String updatedListJson = objectMapper.writeValueAsString(groceryList);

            // Upload the updated grocery list back to S3
            String s3Path = getS3Path(username, listId);
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

    // Method to archive a grocery list to S3 in JSON format
    public String archiveGroceryList(GroceryList groceryList, String username) throws IOException {
        // Ensure the list exists before attempting to archive
        if (groceryList.getId() == null) {
            throw new IllegalArgumentException("Grocery list ID is required.");
        }

        String groceryListID = groceryList.getId();

        // Serialize the GroceryList object to JSON
        ObjectMapper objectMapper = new ObjectMapper();
        String jsonString = objectMapper.writeValueAsString(groceryList);

        // Define the source and destination S3 keys
        String sourceKey = "users/" + username + "/grocery/lists/" + groceryListID + ".json";
        String destinationKey = "users/" + username + "/grocery/archived/" + groceryListID + ".json";

        // Copy the grocery list from the original folder to the archived folder
        try {
            // Upload to archived folder
            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(destinationKey)
                    .build();
            s3Client.putObject(putObjectRequest, RequestBody.fromBytes(jsonString.getBytes()));

            // Delete the original grocery list from the "grocery/lists" folder
            DeleteObjectRequest deleteObjectRequest = DeleteObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(sourceKey)
                    .build();
            s3Client.deleteObject(deleteObjectRequest);

            return destinationKey;  // Return the new S3 path of the archived list
        } catch (Exception e) {
            e.printStackTrace();
            throw new IOException("Failed to archive the grocery list", e);
        }
    }

    // Method to retrieve archived grocery lists from S3
    public List<GroceryList> getArchivedGroceryLists(String username) throws IOException {
        List<GroceryList> archivedLists = new ArrayList<>();

        // Construct the S3 key path to list all archived grocery lists for the user
        String s3Path = "users/" + username + "/grocery/archived/";

        // List all objects in the archived grocery lists folder for the user
        ListObjectsV2Request listObjectsV2Request = ListObjectsV2Request.builder()
                .bucket(BUCKET_NAME)
                .prefix(s3Path)
                .build();

        var objectSummaries = s3Client.listObjectsV2(listObjectsV2Request).contents();

        // For each archived grocery list file, read and parse the content
        for (S3Object object : objectSummaries) {
            String key = object.key();
            var s3Object = s3Client.getObject(b -> b.bucket(BUCKET_NAME).key(key));
            var objectContent = new String(s3Object.readAllBytes());  // Read the content as a String

            // Convert the JSON content to a GroceryList object
            ObjectMapper objectMapper = new ObjectMapper();
            GroceryList groceryList = objectMapper.readValue(objectContent, GroceryList.class);
            archivedLists.add(groceryList);
        }

        return archivedLists;
    }

    // Method to restore an archived grocery list, unchecking all items
    public String restoreArchivedGroceryList(GroceryList groceryList, String username) throws IOException {
        // Ensure the list exists before attempting to restore
        if (groceryList.getId() == null) {
            throw new IllegalArgumentException("Grocery list ID is required.");
        }

        // Uncheck all items in the grocery list
        for (GroceryItem item : groceryList.getItems()) {
            item.setChecked(false); // Set each item's checked status to false
        }

        String groceryListID = groceryList.getId();

        // Serialize the GroceryList object to JSON
        ObjectMapper objectMapper = new ObjectMapper();
        String jsonString = objectMapper.writeValueAsString(groceryList);

        // Define the source and destination S3 keys
        String sourceKey = "users/" + username + "/grocery/archived/" + groceryListID + ".json";
        String destinationKey = "users/" + username + "/grocery/lists/" + groceryListID + ".json";

        // Copy the grocery list from the archived folder to the original folder
        try {
            // Upload to the original folder
            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(destinationKey)
                    .build();
            s3Client.putObject(putObjectRequest, RequestBody.fromBytes(jsonString.getBytes()));

            // Delete the original grocery list from the "grocery/archived" folder
            DeleteObjectRequest deleteObjectRequest = DeleteObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(sourceKey)
                    .build();
            s3Client.deleteObject(deleteObjectRequest);

            return destinationKey;  // Return the new S3 path of the restored list
        } catch (Exception e) {
            e.printStackTrace();
            throw new IOException("Failed to restore the grocery list", e);
        }
    }

    public String generateGroceryListFromMeal(String mealName, String username, String rawOpenAIResponse) throws Exception {
        // Parse the raw JSON response from OpenAI
        ObjectMapper mapper = new ObjectMapper();
        List<GroceryItem> items = new ArrayList<>();
        JsonNode itemsArray;
        
        try {
            itemsArray = mapper.readTree(rawOpenAIResponse);
        } catch (Exception e) {
            throw new IllegalArgumentException("Invalid response format from AI service: " + e.getMessage());
        }
        
        // Generate a UUID for the list
        String listId = UUID.randomUUID().toString().toUpperCase();
        
        // Create grocery items from the items array
        for (JsonNode node : itemsArray) {
            GroceryItem item = new GroceryItem();
            item.setListId(listId);
            item.setId(UUID.randomUUID().toString().toUpperCase());
            
            String itemName = node.has("name") ? node.get("name").asText() : "Unknown Item";
            int quantity = node.has("quantity") ? node.get("quantity").asInt(1) : 1;
            
            item.setName(itemName);
            item.setQuantity(quantity);
            item.setChecked(false);
            item.setPrice(0.0);
            item.setStore("");
    
            // Check if the node has notes and set them if available
            if (node.has("notes")) {
                item.setNotes(node.get("notes").asText());
            } else {
                item.setNotes("");
            }
            
            items.add(item);
        }
        
    
        // Create a new grocery list with all items included
        GroceryList list = new GroceryList();
        list.setId(listId);
        list.setUsername(username);
        list.setName(mealName);
        list.setItems(items);  // Set all items before saving
        list.setAI(true);
        
        // Set timestamps
        String currentTimestamp = String.valueOf(System.currentTimeMillis());
        list.setCreatedAt(currentTimestamp);
        list.setUpdatedAt(currentTimestamp);
    
        // Save the complete list with all items
        String savedListId;
        try {
            savedListId = createGroceryList(list, username);
        } catch (Exception e) {
            throw e;
        }

        // trophy for creating meals from ai
        userProfileService.incrementTrophy(username, "meal-prepper", 1);
    
        return savedListId;
    }
}