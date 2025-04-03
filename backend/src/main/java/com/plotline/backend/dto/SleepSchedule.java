package com.plotline.backend.dto;

import java.util.Date;
import java.util.UUID;

public class SleepSchedule {
    private String id;                // Unique ID for the sleep schedule
    private String username;          // User who owns the schedule
    private Date wakeUpTime;          // Default wake up time
    private Date sleepTime;           // Default sleep time
    private String createdAt;         // When the schedule was created
    private String updatedAt;         // When the schedule was last updated

    // Default constructor
    public SleepSchedule() {}

    // Constructor with fields
    public SleepSchedule(String id, String username, Date wakeUpTime, Date sleepTime) {
        this.id = id != null ? id : UUID.randomUUID().toString();
        this.username = username;
        this.wakeUpTime = wakeUpTime;
        this.sleepTime = sleepTime;
    }

    // Getters and Setters
    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public Date getWakeUpTime() {
        return wakeUpTime;
    }

    public void setWakeUpTime(Date wakeUpTime) {
        this.wakeUpTime = wakeUpTime;
    }

    public Date getSleepTime() {
        return sleepTime;
    }

    public void setSleepTime(Date sleepTime) {
        this.sleepTime = sleepTime;
    }

    public String getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(String createdAt) {
        this.createdAt = createdAt;
    }

    public String getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(String updatedAt) {
        this.updatedAt = updatedAt;
    }
}