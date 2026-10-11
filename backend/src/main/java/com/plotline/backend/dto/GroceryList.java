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
    private String mealID;                 // ID of the meal associated with the grocery list
    private String mealName;               // Name of the meal associated with the grocery list
    private String ownerUsername;          // Username that owns the canonical copy of this list
    private List<String> members;          // Usernames this list is shared with (excludes the owner)
    private String source;                 // "meal" or "goal" for AI lists made since 2026-10; null for typed-in and older lists
    private Double spentAmount;            // archived with "Add to Spending": how much was added to grocery costs...
    private String spentDate;              // ...and on which day ("yyyy-MM-dd"), so restoring can offer to take it back

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

    public Double getSpentAmount() {
        return spentAmount;
    }

    public void setSpentAmount(Double spentAmount) {
        this.spentAmount = spentAmount;
    }

    public String getSpentDate() {
        return spentDate;
    }

    public void setSpentDate(String spentDate) {
        this.spentDate = spentDate;
    }

    public String getSource() {
        return source;
    }

    public void setSource(String source) {
        this.source = source;
    }

    public String getMealID() {
        return mealID;
    }

    public void setMealID(String mealID) {
        this.mealID = mealID;
    }

    public String getMealName() {
        return mealName;
    }

    public void setMealName(String mealName) {
        this.mealName = mealName;
    }

    public String getOwnerUsername() {
        return ownerUsername;
    }

    public void setOwnerUsername(String ownerUsername) {
        this.ownerUsername = ownerUsername;
    }

    public List<String> getMembers() {
        return members;
    }

    public void setMembers(List<String> members) {
        this.members = members;
    }
}
