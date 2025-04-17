package com.plotline.backend.dto;

public class Trophy {
  private String id; // e.g., "long_term_goals"
    private String name; // e.g., "Goal Crusher"
    private String description; // e.g., "Complete long-term goals"
    private int level; // 0 = none, 1 = bronze, 2 = silver, 3 = gold, 4 = diamond
    private int progress; // how many actions have been completed
    private int[] thresholds; // e.g., {0, 5, 10, 20, 50} for each level
    private String earnedDate; // format: "yyyy-MM-dd'T'HH:mm:ssZ"


    // Constructor
    public Trophy() {
        // Default constructor
    }

    // Constructor with parameters
    public Trophy(String id, String name, String description, int level, int progress, int[] thresholds, String earnedDate) {
        this.id = id;
        this.name = name;
        this.description = description;
        this.level = level;
        this.progress = progress;
        this.thresholds = thresholds;
        this.earnedDate = earnedDate;
    }

    // Getters and Setters
    public String getId() {
        return id;
    }
    public void setId(String id) {
        this.id = id;
    }
    public String getName() {
        return name;
    }
    public void setName(String name) {
        this.name = name;
    }
    public String getDescription() {
        return description;
    }
    public void setDescription(String description) {
        this.description = description;
    }
    public int getLevel() {
        return level;
    }
    public void setLevel(int level) {
        this.level = level;
    }
    public int getProgress() {
        return progress;
    }
    public void setProgress(int progress) {
        this.progress = progress;
    }
    public int[] getThresholds() {
        return thresholds;
    }
    public void setThresholds(int[] thresholds) {
        this.thresholds = thresholds;
    }
    public String getEarnedDate() {
        return earnedDate;
    }
    public void setEarnedDate(String earnedDate) {
        this.earnedDate = earnedDate;
    }
}
