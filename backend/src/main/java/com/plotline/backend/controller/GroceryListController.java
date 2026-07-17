package com.plotline.backend.controller;
import com.plotline.backend.service.OpenAIService;

import com.plotline.backend.dto.GroceryItem;
import com.plotline.backend.dto.GroceryList;
import com.plotline.backend.service.DietaryRestrictionsService;
import com.plotline.backend.service.GroceryListService;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.plotline.backend.dto.DietaryRestrictions;
import com.plotline.backend.dto.GroceryCostEstimateRequest;
import com.plotline.backend.dto.GroceryListInvite;

import org.apache.http.HttpStatus;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/groceryLists")
public class GroceryListController {

    @Autowired
    private GroceryListService groceryListService;

    @Autowired
    private OpenAIService openAIService;

    @Autowired
    private DietaryRestrictionsService dietaryRestrictionsService;


    // Create grocery list
    @PostMapping("/create-grocery-list")
    public ResponseEntity<String> createGroceryList(@RequestBody GroceryList groceryList) {
        try {
            String temp = groceryListService.createGroceryList(groceryList, groceryList.getUsername());
            return ResponseEntity.ok(temp);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body("Error: " + e.getMessage());
        } catch (IOException e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error saving grocery list: " + e.getMessage());
        }
    }

    // Get all grocery lists for a specific user
    @GetMapping("/get-grocery-lists/{username}")
    public ResponseEntity<List<GroceryList>> getGroceryLists(@PathVariable String username) {
        try {
            List<GroceryList> groceryLists = groceryListService.getGroceryListsForUser(username);
            return ResponseEntity.ok(groceryLists);
        } catch (IOException e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body(null);
        }
    }

    // Get items from a grocery list
    @GetMapping("/{listId}/items")
    public ResponseEntity<List<GroceryItem>> getItems(@PathVariable String listId, @RequestParam String username) {
        List<GroceryItem> items = groceryListService.getItems(username, listId);
        return ResponseEntity.ok(items);
    }

    // Get a single grocery list, including its current shared members (canonical copy)
    @GetMapping("/{listId}/details")
    public ResponseEntity<GroceryList> getGroceryListDetails(@PathVariable String listId, @RequestParam String username) {
        GroceryList list = groceryListService.getGroceryList(username, listId);
        if (list == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(list);
    }

    // Add item to the grocery list
    @PostMapping("/{listId}/items")
    public ResponseEntity<String> addItem(@PathVariable String listId, @RequestParam String username, @RequestBody GroceryItem item) {
        boolean success = groceryListService.addItem(username, listId, item);
        if (success) {
            return ResponseEntity.ok("Item added successfully");
        } else {
            return ResponseEntity.status(400).body("Failed to add item");
        }
    }

    // Delete an entire grocery list
    @DeleteMapping("/{listId}")
    public ResponseEntity<String> deleteGroceryList(@PathVariable String listId, @RequestParam String username) {
        boolean success = groceryListService.deleteGroceryList(username, listId);
        if (success) {
            return ResponseEntity.ok("Grocery list deleted successfully");
        } else {
            return ResponseEntity.status(500).body("Failed to delete grocery list");
        }
    }

    // Delete an item from the grocery list
    @DeleteMapping("/{listId}/items/{itemId}")
    public ResponseEntity<String> deleteItem(@PathVariable String listId, @PathVariable String itemId, @RequestParam String username) {
        boolean success = groceryListService.deleteItem(username, listId, itemId);
        if (success) {
            return ResponseEntity.ok("Item deleted successfully");
        } else {
            return ResponseEntity.status(400).body("Failed to delete item");
        }
    }

    // Toggle the checked status of an item in the grocery list
    @PatchMapping("/{listId}/items/{itemId}/toggle")
    public ResponseEntity<String> toggleItemCheckedStatus(@PathVariable String listId, @PathVariable String itemId, @RequestParam String username) {
        boolean success = groceryListService.toggleChecked(username, listId, itemId);
        if (success) {
            return ResponseEntity.ok("Item checked status toggled successfully");
        } else {
            return ResponseEntity.status(400).body("Failed to toggle item checked status");
        }
    }

    // Endpoint to update the details of an item in the grocery list
    @PutMapping("/{listId}/items/{itemId}")
    public ResponseEntity<String> updateItemDetails(@PathVariable String listId, @RequestParam String username, @RequestBody GroceryItem updatedItem) {
        boolean success = groceryListService.updateItemDetails(username, listId, updatedItem);
        if (success) {
            return ResponseEntity.ok("Item details updated successfully.");
        } else {
            return ResponseEntity.status(400).body("Failed to update item details.");
        }
    }

    // Endpoint to archive a grocery list
    @PostMapping("/archive/{username}")
    public ResponseEntity<String> archiveGroceryList(@PathVariable String username, @RequestBody GroceryList groceryList) {
        try {
            // Ensure that the grocery list object has a valid ID
            if (groceryList.getId() == null) {
                return ResponseEntity.status(HttpStatus.SC_BAD_REQUEST).body("Grocery list must have a valid ID.");
            }
            // Call the service method to archive the grocery list
            String result = groceryListService.archiveGroceryList(groceryList, username);
            // Return a success response with the new path of the archived list
            return ResponseEntity.ok("Grocery list archived successfully at: " + result);
        } catch (IOException e) {
            // Handle any IO exceptions, e.g., if there's a problem interacting with S3
            return ResponseEntity.status(HttpStatus.SC_INTERNAL_SERVER_ERROR).body("Failed to archive grocery list: " + e.getMessage());
        }
    }

    // Endpoing to view archived grocery lists
    @GetMapping("/archived/{username}")
    public ResponseEntity<List<GroceryList>> getArchivedGroceryLists(@PathVariable String username) {
        try {
            // Call the service method to retrieve the archived grocery lists
            List<GroceryList> archivedLists = groceryListService.getArchivedGroceryLists(username);
            // Return the list of archived grocery lists
            return ResponseEntity.ok(archivedLists);
        } catch (IOException e) {
            // Handle any IO exceptions, e.g., if there's a problem interacting with S3
            return ResponseEntity.status(HttpStatus.SC_INTERNAL_SERVER_ERROR).body(null);
        }
    }

    // Permanently delete a single archived grocery list
    @DeleteMapping("/archived/{username}/{listId}")
    public ResponseEntity<String> deleteArchivedGroceryList(@PathVariable String username, @PathVariable String listId) {
        try {
            groceryListService.deleteArchivedGroceryList(username, listId);
            return ResponseEntity.ok("Archived grocery list deleted.");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("Error deleting archived list: " + e.getMessage());
        }
    }

    // Permanently delete all archived grocery lists for a user
    @DeleteMapping("/archived/{username}")
    public ResponseEntity<String> deleteAllArchivedGroceryLists(@PathVariable String username) {
        try {
            groceryListService.deleteAllArchivedGroceryLists(username);
            return ResponseEntity.ok("All archived grocery lists deleted.");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("Error deleting archived lists: " + e.getMessage());
        }
    }

    // Endpoint to restore an archived grocery list
    @PostMapping("/restore/{username}")
    public ResponseEntity<String> restoreGroceryList(@PathVariable String username, @RequestBody GroceryList groceryList) {
        try {
            // Ensure that the grocery list object has a valid ID
            if (groceryList.getId() == null) {
                return ResponseEntity.status(HttpStatus.SC_BAD_REQUEST).body("Grocery list must have a valid ID.");
            }
            // Call the service method to restore the grocery list
            String result = groceryListService.restoreArchivedGroceryList(groceryList, username);
            // Return a success response with the new path of the restored list
            return ResponseEntity.ok("Grocery list restored successfully at: " + result);
        } catch (IOException e) {
            // Handle any IO exceptions, e.g., if there's a problem interacting with S3
            return ResponseEntity.status(HttpStatus.SC_INTERNAL_SERVER_ERROR).body("Failed to restore grocery list: " + e.getMessage());
        }
    }

    // Endpoint to estimate cost of groccery items
    @PostMapping("/estimate-grocery-cost")
    public ResponseEntity<Double> estimateGroceryCost(@RequestBody GroceryCostEstimateRequest request) {
        try {
            String location = request.getLocation() != null ? request.getLocation() : "United States";
            StringBuilder sb = new StringBuilder("Estimate the total cost in USD of buying the following groceries in " + location +
            ". Here are the groceries to get an average cost of with quantities:\n"
            );

            for (GroceryItem item : request.getItems()) {
                sb.append(item.getQuantity()).append(" x ").append(item.getName()).append("\n");
            }

            String response = openAIService.generateResponseGC(sb.toString());
            Double estimatedCost = Double.parseDouble(response);
            return ResponseEntity.ok(estimatedCost);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.SC_INTERNAL_SERVER_ERROR)
                    .body(-1.0);
        }
    }

    @PostMapping("/generate-from-meal")
    public ResponseEntity<String> generateListFromMeal(@RequestBody Map<String, String> request) {
        try {
            // Extract meal name and username from the request
            String mealName = request.get("mealName");
            String username = request.get("username");
    
            // Validate input
            if (mealName == null || mealName.trim().isEmpty()) {
                return ResponseEntity.badRequest().body("Meal name is required");
            }
    
            if (username == null || username.trim().isEmpty()) {
                return ResponseEntity.badRequest().body("Username is required");
            }

            // Parse the response to determine the outcome
            ObjectMapper mapper = new ObjectMapper();
            JsonNode rootNode;
    
            // Fetch dietary restrictions for the user
            DietaryRestrictions dietaryRestrictions = null;
            try {
                dietaryRestrictions = dietaryRestrictionsService.getDietaryRestrictions(username);
            } catch (Exception e) {
                // If we can't get dietary restrictions, create default ones (all false)
                dietaryRestrictions = new DietaryRestrictions();
                dietaryRestrictions.setUsername(username);
            }

            // Get raw response from OpenAI, passing dietary restrictions
            String rawResponse = openAIService.generateGroceryListFromMeal(
                    "Meal: " + mealName, 
                    dietaryRestrictions
            );

            try {
                rootNode = mapper.readTree(rawResponse);
            } catch (Exception e) {
                return ResponseEntity.status(500).body("Invalid response from AI service: " + e.getMessage());
            }

            // Case 1: Meal is incompatible with dietary restrictions
            if (rootNode.has("incompatible") && rootNode.get("incompatible").asBoolean()) {
                // Return the incompatibility message to the frontend
                String response = "INCOMPATIBLE:" + rawResponse;
                return ResponseEntity.ok(response);
            }

            // Case 2: Meal requires modifications for dietary restrictions
            if (rootNode.has("modifications")) {
                String modifications = rootNode.get("modifications").asText();
                JsonNode itemsNode = rootNode.get("items");

                if (itemsNode == null || !itemsNode.isArray()) {
                    return ResponseEntity.status(500).body("Invalid response format: missing items array");
                }

                // Generate the grocery list with the modified items
                String listId = groceryListService.generateGroceryListFromMeal(
                    mealName + " (Modified for dietary restrictions)",
                    username,
                    mapper.writeValueAsString(itemsNode)
                );

                // Return a special response indicating modifications were made
                Map<String, String> modResponse = new HashMap<>();
                modResponse.put("modifications", modifications);
                modResponse.put("listId", listId);

                String responseStr = "MODIFIED:" + mapper.writeValueAsString(modResponse);
                return ResponseEntity.ok(responseStr);
            }

            // Case 3: Standard success case - meal works with dietary restrictions
            String listId = groceryListService.generateGroceryListFromMeal(mealName, username, rawResponse);
            return ResponseEntity.ok(listId);

        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error generating grocery list from meal: " + e.getMessage());
        }
    }

    @PostMapping("/generate-meal-from-list")
    public ResponseEntity<String> generateMealFromList(@RequestBody Map<String, Object> request) {
        try {
            if (request == null) {
                System.out.println("Received a null request.");
            }

            // Extract the grocery items list and username from the request
            List<Map<String, Object>> groceryItems = (List<Map<String, Object>>) request.get("items");
            String username = (String) request.get("username");
            String listId = (String) request.get("listId");

            if (groceryItems == null || groceryItems.isEmpty()) {
                return ResponseEntity.badRequest().body("Grocery items list is required");
            }

            if (username == null || username.trim().isEmpty()) {
                return ResponseEntity.badRequest().body("Username is required");
            }

            // Fetch dietary restrictions for the user
            DietaryRestrictions dietaryRestrictions = dietaryRestrictionsService.getDietaryRestrictions(username);

            // Call OpenAIService to generate a meal suggestion from the grocery list
            String mealRecipe = openAIService.generateMealFromGroceryList(username, listId, groceryItems, dietaryRestrictions);

            // Return the generated meal recipe or any error messages
            return ResponseEntity.ok(mealRecipe);

        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error generating meal from list: " + e.getMessage());
        }
    }

    // Get cost of the groccery item live (as soon as user inputs it into the list)
    @PostMapping("/estimate-grocery-cost-live")
    public ResponseEntity<Double> estimateGroceryCost2(@RequestBody GroceryCostEstimateRequest request) {
        try {
            double cost = openAIService.estimateGroceryCost(request);
            return ResponseEntity.ok(cost);
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity
                .status(HttpStatus.SC_INTERNAL_SERVER_ERROR)
                .body(-1.0);
        }
    }

    // Share a grocery list with another user
    @PostMapping("/share")
    public ResponseEntity<?> shareGroceryList(@RequestBody Map<String, String> body) {
        try {
            String fromUsername = body.get("fromUsername");
            String toUsername   = body.get("toUsername");
            String listId       = body.get("listId");
            if (fromUsername == null || toUsername == null || listId == null) {
                return ResponseEntity.badRequest().body("fromUsername, toUsername, and listId are required.");
            }
            GroceryListInvite invite = groceryListService.shareGroceryList(fromUsername, toUsername, listId);
            return ResponseEntity.ok(invite);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error sharing grocery list: " + e.getMessage());
        }
    }

    // Get pending incoming grocery list invites for a user
    @GetMapping("/share/pending")
    public ResponseEntity<?> getPendingGroceryInvites(@RequestParam String username) {
        try {
            List<GroceryListInvite> invites = groceryListService.getPendingGroceryInvites(username);
            return ResponseEntity.ok(invites);
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error fetching invites: " + e.getMessage());
        }
    }

    // Owner removes a member from a shared list (unshare)
    @PostMapping("/unshare")
    public ResponseEntity<String> unshareGroceryList(@RequestBody Map<String, String> body) {
        try {
            String ownerUsername  = body.get("ownerUsername");
            String listId         = body.get("listId");
            String memberUsername = body.get("memberUsername");
            if (ownerUsername == null || listId == null || memberUsername == null) {
                return ResponseEntity.badRequest().body("ownerUsername, listId, and memberUsername are required.");
            }
            boolean ok = groceryListService.unshareGroceryList(ownerUsername, listId, memberUsername);
            return ok
                ? ResponseEntity.ok("Member removed from shared list.")
                : ResponseEntity.badRequest().body("Only the list owner can remove members.");
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error removing member: " + e.getMessage());
        }
    }

    // Accept or decline a grocery list invite
    @PostMapping("/share/respond")
    public ResponseEntity<String> respondToGroceryShare(@RequestBody Map<String, String> body) {
        try {
            String recipientUsername = body.get("recipientUsername");
            String inviteId          = body.get("inviteId");
            boolean accept           = Boolean.parseBoolean(body.get("accept"));
            if (recipientUsername == null || inviteId == null) {
                return ResponseEntity.badRequest().body("recipientUsername and inviteId are required.");
            }
            groceryListService.respondToGroceryShare(recipientUsername, inviteId, accept);
            return ResponseEntity.ok(accept ? "List added to your active lists." : "Invite declined.");
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error responding to invite: " + e.getMessage());
        }
    }

    @PostMapping("/generate-list-from-goal")
    public ResponseEntity<String> generateListFromGoal(@RequestBody Map<String, String> request) {
        try {
            String goal = request.get("goal");
            String username = request.get("username");

            if (goal == null || goal.trim().isEmpty()) {
                return ResponseEntity.badRequest().body("{\"error\": \"Goal is required\"}");
            }

            if (username == null || username.trim().isEmpty()) {
                return ResponseEntity.badRequest().body("{\"error\": \"Username is required\"}");
            }

            // Call OpenAIService to generate a grocery list based on the goal
            String groceryListJson = openAIService.generateGroceryListFromGoal(goal, username);

            // Parse the title from the JSON response to use as list name
            ObjectMapper mapper = new ObjectMapper();
            JsonNode rootNode = mapper.readTree(groceryListJson);
            String listTitle = rootNode.has("title") ? rootNode.get("title").asText() : "Grocery List for " + goal;
            
            // Extract items array
            JsonNode itemsNode = rootNode.get("items");
            if (itemsNode == null || !itemsNode.isArray()) {
                return ResponseEntity.status(500).body("Invalid response format: missing items array");
            }
            
            // Generate the grocery list and save it to S3
            String listId = groceryListService.generateGroceryListFromMeal(listTitle, username, mapper.writeValueAsString(itemsNode));
            
            // Return the list ID and the full JSON response
            Map<String, String> response = new HashMap<>();
            response.put("listId", listId);
            response.put("data", groceryListJson);
            
            return ResponseEntity.ok(mapper.writeValueAsString(response));
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error generating grocery list from goal: " + e.getMessage());
        }
    }
}

