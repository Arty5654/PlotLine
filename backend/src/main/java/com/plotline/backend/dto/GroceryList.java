package com.plotline.backend.dto;

import java.util.List;

public class GroceryList {
    private String id;                      // Unique ID for the list
    private String username;                // User who owns the list
    private String name;                    // Name of the grocery list
    private String createdAt;               // Date when the list was created
    private String updatedAt;               // Date when the list was last updated
    private boolean isAI = false;           // Whether the list was AI-generated or not
    private List<GroceryItem> items;        // List of grocery items in the list

    // Default constructor
    public GroceryList() {}

    // Getters and Setters
    public String getId() {
        return id;
    }

    public void setId(String groceryListID) {
        this.id = groceryListID;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(String createdAt) {
        this.createdAt = createdAt;
    }

    public String getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(String updatedAt) {
        this.updatedAt = updatedAt;
    }

    public boolean isAI() {
        return isAI;
    }

    public void setAI(boolean AI) {
        isAI = AI;
    }

    public List<GroceryItem> getItems() {
        return items;
    }

    public void setItems(List<GroceryItem> items) {
        this.items = items;
    }
}
