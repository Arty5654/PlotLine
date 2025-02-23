package com.plotline.backend.controller;

import com.plotline.backend.dto.GroceryItem;
import com.plotline.backend.dto.GroceryList;
import com.plotline.backend.service.GroceryListService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.util.List;

@RestController
@RequestMapping("/api/groceryLists")
public class GroceryListController {

    @Autowired
    private GroceryListService groceryListService;

    // Create grocery list (same as previous code)
    @PostMapping("/create-grocery-list")
    public ResponseEntity<String> createGroceryList(@RequestBody GroceryList groceryList) {
        try {
            String temp = groceryListService.createGroceryList(groceryList, groceryList.getUsername());
            return ResponseEntity.ok("Grocery list created successfully with name: " + groceryList.getName() + "and path " + temp);
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

    @GetMapping("/{listId}/items")
    public ResponseEntity<List<GroceryItem>> getItems(@PathVariable String listId, @RequestParam String username) {
        List<GroceryItem> items = groceryListService.getItems(username, listId);
        return ResponseEntity.ok(items);
    }

    @PostMapping("/{listId}/items")
    public ResponseEntity<String> addItem(@PathVariable String listId, @RequestParam String username, @RequestBody GroceryItem item) {
        boolean success = groceryListService.addItem(username, listId, item);
        if (success) {
            return ResponseEntity.ok("Item added successfully");
        } else {
            return ResponseEntity.status(400).body("Failed to add item");
        }
    }

    @DeleteMapping("/{listId}/items/{itemId}")
    public ResponseEntity<String> deleteItem(@PathVariable String listId, @PathVariable String itemId, @RequestParam String username) {
        boolean success = groceryListService.deleteItem(username, listId, itemId);
        if (success) {
            return ResponseEntity.ok("Item deleted successfully");
        } else {
            return ResponseEntity.status(400).body("Failed to delete item");
        }
    }
}

