package com.plotline.backend.dto;

import java.util.Date;
import java.util.UUID;

public class HealthEntry {
    private String id;                // Unique ID for the health entry
    private String username;          // User who owns the entry
    private Date date;                // Date of the health entry
    private Date wakeUpTime;          // Wake up time
    private Date sleepTime;           // Sleep time
    private int hoursSlept;           // Hours slept
    private String mood;              // Mood emoji selected by user
    private String notes;             // Additional notes
    private String createdAt;         // When the entry was created
    private String updatedAt;         // When the entry was last updated

    // Default constructor
    public HealthEntry() {}

    // Constructor with fields
    public HealthEntry(String id, String username, Date date, Date wakeUpTime, Date sleepTime, 
                       int hoursSlept, String mood, String notes) {
        this.id = id != null ? id : UUID.randomUUID().toString();
        this.username = username;
        this.date = date;
        this.wakeUpTime = wakeUpTime;
        this.sleepTime = sleepTime;
        this.hoursSlept = hoursSlept;
        this.mood = mood;
        this.notes = notes;
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

    public Date getDate() {
        return date;
    }

    public void setDate(Date date) {
        this.date = date;
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

    public int getHoursSlept() {
        return hoursSlept;
    }

    public void setHoursSlept(int hoursSlept) {
        this.hoursSlept = hoursSlept;
    }

    public String getMood() {
        return mood;
    }

    public void setMood(String mood) {
        this.mood = mood;
    }

    public String getNotes() {
        return notes;
    }

    public void setNotes(String notes) {
        this.notes = notes;
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