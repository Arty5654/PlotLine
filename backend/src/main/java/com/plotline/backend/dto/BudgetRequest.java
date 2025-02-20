package com.plotline.backend.dto;

import java.util.Map;

public class BudgetRequest {
    private String username;
    private String type; // Weekly or Monthly
    private Map<String, Double> budget; // Category -> Amount

    // Constructors
    public BudgetRequest() {}

    public BudgetRequest(String username, String type, Map<String, Double> budget) {
        this.username = username;
        this.type = type;
        this.budget = budget;
    }

    // Getters and Setters
    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    public Map<String, Double> getBudget() {
        return budget;
    }

    public void setBudget(Map<String, Double> budget) {
        this.budget = budget;
    }
}
