package com.plotline.backend.dto;

public class SubscriptionStatus {
    private String plan;          // "trial", "paid", "lifetime"
    private double monthlyPrice;  // 0 for lifetime
    private String trialEndsAt;   // ISO yyyy-MM-dd, null for lifetime/paid
    private boolean autoRenews;   // true if will convert to paid
    private String message;       // helper copy

    public SubscriptionStatus() {}

    public SubscriptionStatus(String plan, double monthlyPrice, String trialEndsAt, boolean autoRenews, String message) {
        this.plan = plan;
        this.monthlyPrice = monthlyPrice;
        this.trialEndsAt = trialEndsAt;
        this.autoRenews = autoRenews;
        this.message = message;
    }

    public String getPlan() { return plan; }
    public void setPlan(String plan) { this.plan = plan; }

    public double getMonthlyPrice() { return monthlyPrice; }
    public void setMonthlyPrice(double monthlyPrice) { this.monthlyPrice = monthlyPrice; }

    public String getTrialEndsAt() { return trialEndsAt; }
    public void setTrialEndsAt(String trialEndsAt) { this.trialEndsAt = trialEndsAt; }

    public boolean isAutoRenews() { return autoRenews; }
    public void setAutoRenews(boolean autoRenews) { this.autoRenews = autoRenews; }

    public String getMessage() { return message; }
    public void setMessage(String message) { this.message = message; }
}
