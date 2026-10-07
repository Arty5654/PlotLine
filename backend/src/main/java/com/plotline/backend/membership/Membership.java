package com.plotline.backend.membership;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * A user's membership, stored at users/{username}/subscription.json.
 *
 * plan: "lifetime" (the first 1,000 accounts, free forever), "free-week" (every new account's
 * first week, no payment needed), "trial" (the App Store's free month, once they subscribe),
 * "monthly" (paid), or "none" (no membership). Everything but lifetime and none unlocks the app
 * until {@code expiresAt}. Files from the old server-side trial ("grace", "needs-trial", ...) are
 * {@link #isLegacy() legacy} and get decided again.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public class Membership {

    public static final String LIFETIME = "lifetime";
    public static final String FREE_WEEK = "free-week";
    public static final String TRIAL = "trial";
    public static final String MONTHLY = "monthly";
    public static final String NONE = "none";

    private String plan;
    private Long expiresAt;               // when access ends (epoch millis), including Apple's billing grace period
    private Long transactionExpiresAt;    // the latest App Store transaction's own expiry, to ignore older updates
    private Boolean autoRenews;           // null until Apple tells us
    private boolean revoked;              // refunded or revoked by Apple
    private String originalTransactionId; // the App Store subscription this account uses
    private String environment;           // "Production" or "Sandbox"

    public Membership() { }

    public static Membership of(String plan) {
        Membership membership = new Membership();
        membership.plan = plan;
        return membership;
    }

    @JsonIgnore
    public boolean isActive(long now) {
        if (LIFETIME.equals(plan)) return true;
        if (!FREE_WEEK.equals(plan) && !TRIAL.equals(plan) && !MONTHLY.equals(plan)) return false;
        return !revoked && expiresAt != null && now < expiresAt;
    }

    /** written by the old server-side trial, before App Store purchases */
    @JsonIgnore
    public boolean isLegacy() {
        if (TRIAL.equals(plan) || FREE_WEEK.equals(plan)) return expiresAt == null;
        return !LIFETIME.equals(plan) && !MONTHLY.equals(plan) && !NONE.equals(plan);
    }

    public String getPlan() { return plan; }
    public void setPlan(String plan) { this.plan = plan; }

    public Long getExpiresAt() { return expiresAt; }
    public void setExpiresAt(Long expiresAt) { this.expiresAt = expiresAt; }

    public Long getTransactionExpiresAt() { return transactionExpiresAt; }
    public void setTransactionExpiresAt(Long transactionExpiresAt) { this.transactionExpiresAt = transactionExpiresAt; }

    public Boolean getAutoRenews() { return autoRenews; }
    public void setAutoRenews(Boolean autoRenews) { this.autoRenews = autoRenews; }

    public boolean isRevoked() { return revoked; }
    public void setRevoked(boolean revoked) { this.revoked = revoked; }

    public String getOriginalTransactionId() { return originalTransactionId; }
    public void setOriginalTransactionId(String originalTransactionId) { this.originalTransactionId = originalTransactionId; }

    public String getEnvironment() { return environment; }
    public void setEnvironment(String environment) { this.environment = environment; }
}
