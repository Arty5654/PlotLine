package com.plotline.backend.dto;

import java.util.List;

public class GroceryCostEstimateRequest {
    private String location;
    private List<GroceryItem> items;

    // Getters and Setters
    public String getLocation() {
        return location;
    }

    public void setLocation(String location) {
        this.location = location;
    }

    public List<GroceryItem> getItems() {
        return items;
    }

    public void setItems(List<GroceryItem> items) {
        this.items = items;
    }
}
