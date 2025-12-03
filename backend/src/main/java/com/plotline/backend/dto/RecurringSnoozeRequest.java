package com.plotline.backend.dto;

public class RecurringSnoozeRequest {
    private String username;
    private String snoozeKey;
    private Integer months;

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public String getSnoozeKey() { return snoozeKey; }
    public void setSnoozeKey(String snoozeKey) { this.snoozeKey = snoozeKey; }

    public Integer getMonths() { return months; }
    public void setMonths(Integer months) { this.months = months; }
}
