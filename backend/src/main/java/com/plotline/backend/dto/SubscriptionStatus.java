package com.plotline.backend.dto;

public class SubscriptionStatus {
    private String plan;          // "trial", "paid", "lifetime"
    private double monthlyPrice;  // 0 for lifetime
    private String trialEndsAt;   // ISO yyyy-MM-dd, null for lifetime/paid
    private boolean autoRenews;   // true if will convert to paid
    private String message;       // helper copy
    private String graceEndsAt;   // ISO date for initial free month
    private boolean cancelled;    // user cancelled auto-renew/plan

    public SubscriptionStatus() {}

    public SubscriptionStatus(String plan, double monthlyPrice, String trialEndsAt, boolean autoRenews, String message) {
        this.plan = plan;
        this.monthlyPrice = monthlyPrice;
        this.trialEndsAt = trialEndsAt;
        this.autoRenews = autoRenews;
        this.message = message;
    }

    public SubscriptionStatus(String plan, double monthlyPrice, String trialEndsAt, boolean autoRenews, String message, String graceEndsAt, boolean cancelled) {
        this.plan = plan;
        this.monthlyPrice = monthlyPrice;
        this.trialEndsAt = trialEndsAt;
        this.autoRenews = autoRenews;
        this.message = message;
        this.graceEndsAt = graceEndsAt;
        this.cancelled = cancelled;
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

    public String getGraceEndsAt() { return graceEndsAt; }
    public void setGraceEndsAt(String graceEndsAt) { this.graceEndsAt = graceEndsAt; }

    public boolean isCancelled() { return cancelled; }
    public void setCancelled(boolean cancelled) { this.cancelled = cancelled; }
}
