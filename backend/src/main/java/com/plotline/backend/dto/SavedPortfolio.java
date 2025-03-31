package com.plotline.backend.dto;

public class SavedPortfolio {
    private String username;
    private String portfolio;           // Current version (may be edited by user)
    private String originalPortfolio;   // Original LLM-generated portfolio
    private String riskTolerance;

    // Constructors
    public SavedPortfolio() {}

    public SavedPortfolio(String username, String portfolio, String originalPortfolio, String riskTolerance) {
        this.username = username;
        this.portfolio = portfolio;
        this.originalPortfolio = originalPortfolio;
        this.riskTolerance = riskTolerance;
    }

    // Getters
    public String getUsername() {
        return username;
    }

    public String getPortfolio() {
        return portfolio;
    }

    public String getOriginalPortfolio() {
        return originalPortfolio;
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

    public void setOriginalPortfolio(String originalPortfolio) {
        this.originalPortfolio = originalPortfolio;
    }

    public void setRiskTolerance(String riskTolerance) {
        this.riskTolerance = riskTolerance;
    }
}
