package com.plotline.backend.dto;

public class RecurringChargePrompt {
    private String snoozeKey;
    private String name;
    private double averageAmount;
    private int dayOfMonth;
    private int consecutiveMonths;
    private String lastSeen;          // ISO date
    private String nextReminderAfter; // ISO date when snooze would expire

    public RecurringChargePrompt() {}

    public RecurringChargePrompt(String snoozeKey, String name, double averageAmount, int dayOfMonth, int consecutiveMonths, String lastSeen, String nextReminderAfter) {
        this.snoozeKey = snoozeKey;
        this.name = name;
        this.averageAmount = averageAmount;
        this.dayOfMonth = dayOfMonth;
        this.consecutiveMonths = consecutiveMonths;
        this.lastSeen = lastSeen;
        this.nextReminderAfter = nextReminderAfter;
    }

    public String getSnoozeKey() { return snoozeKey; }
    public void setSnoozeKey(String snoozeKey) { this.snoozeKey = snoozeKey; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public double getAverageAmount() { return averageAmount; }
    public void setAverageAmount(double averageAmount) { this.averageAmount = averageAmount; }

    public int getDayOfMonth() { return dayOfMonth; }
    public void setDayOfMonth(int dayOfMonth) { this.dayOfMonth = dayOfMonth; }

    public int getConsecutiveMonths() { return consecutiveMonths; }
    public void setConsecutiveMonths(int consecutiveMonths) { this.consecutiveMonths = consecutiveMonths; }

    public String getLastSeen() { return lastSeen; }
    public void setLastSeen(String lastSeen) { this.lastSeen = lastSeen; }

    public String getNextReminderAfter() { return nextReminderAfter; }
    public void setNextReminderAfter(String nextReminderAfter) { this.nextReminderAfter = nextReminderAfter; }
}
