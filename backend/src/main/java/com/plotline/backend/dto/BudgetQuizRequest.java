package com.plotline.backend.dto;

public class BudgetQuizRequest {
    private String username;
    private double yearlyIncome;
    private int dependents;
    private String location;  // city, state
    private String spendingStyle; // e.g. frugal, moderate, lavish

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public double getYearlyIncome() { return yearlyIncome; }
    public void setYearlyIncome(double yearlyIncome) { this.yearlyIncome = yearlyIncome; }

    public int getDependents() { return dependents; }
    public void setDependents(int dependents) { this.dependents = dependents; }

    public String getLocation() { return location; }
    public void setLocation(String location) { this.location = location; }

    public String getSpendingStyle() { return spendingStyle; }
    public void setSpendingStyle(String spendingStyle) { this.spendingStyle = spendingStyle; }
}
