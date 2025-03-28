package com.plotline.backend.dto;

public class SavedPortfolio {
    private String username;
    private String portfolio;
    private String riskTolerance;

    public SavedPortfolio() {}

    public SavedPortfolio(String username, String portfolio, String riskTolerance) {
        this.username = username;
        this.portfolio = portfolio;
        this.riskTolerance = riskTolerance;
    }

    // Getters
    public String getUsername() {
        return username;
    }

    public String getPortfolio() {
        return portfolio;
    }

    public String getRiskTolerance() {
        return riskTolerance;
    }

    // Setters
    public void setUsername(String username) {
        this.username = username;
    }

    public void setPortfolio(String portfolio) {
        this.portfolio = portfolio;
    }

    public void setRiskTolerance(String riskTolerance) {
        this.riskTolerance = riskTolerance;
    }

    @Override
    public String toString() {
        return "SavedPortfolio{" +
                "username='" + username + '\'' +
                ", portfolio='" + portfolio + '\'' +
                ", riskTolerance='" + riskTolerance + '\'' +
                '}';
    }
}
