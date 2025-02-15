package com.plotline.backend.dto;

import java.util.Map;

public class WeeklyMonthlyCostRequest {
    private String username;
    private String type; // "weekly" or "monthly"
    private Map<String, Double> costs; // Stores category & amount

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

    public Map<String, Double> getCosts() {
        return costs;
    }

    public void setCosts(Map<String, Double> costs) {
        this.costs = costs;
    }
}
