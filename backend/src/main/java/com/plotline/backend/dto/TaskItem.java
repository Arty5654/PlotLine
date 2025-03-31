package com.plotline.backend.dto;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonProperty;

public class TaskItem {

  private int id;
  private String name;
  private boolean isCompleted;
  private Priority priority;

  // --- Priority enum ---
  public enum Priority {
    High,
    Medium,
    Low;

    @JsonCreator
    public static Priority fromString(String value) {
      return switch (value.toLowerCase()) {
        case "high" -> High;
        case "medium" -> Medium;
        case "low" -> Low;
        default -> Medium; // fallback default
      };
    }
  }

  // --- Default constructor (for Jackson) ---
  public TaskItem() {
  }

  public TaskItem(@JsonProperty("id") int id,
      @JsonProperty("name") String name,
      @JsonProperty("completed") boolean isCompleted,
      @JsonProperty("priority") Priority priority) {
    this.id = id;
    this.name = name;
    this.isCompleted = isCompleted;
    this.priority = priority;
  }

  // --- Getters & Setters ---
  public int getId() {
    return id;
  }

  public void setId(int id) {
    this.id = id;
  }

  public String getName() {
    return name;
  }

  public void setName(String name) {
    this.name = name;
  }

  public boolean isCompleted() {
    return isCompleted;
  }

  public void setCompleted(boolean completed) {
    isCompleted = completed;
  }

  public Priority getPriority() {
    return priority;
  }

  public void setPriority(Priority priority) {
    this.priority = priority;
  }

  @Override
  public String toString() {
    return "TaskItem{" +
        "id=" + id +
        ", name='" + name + '\'' +
        ", isCompleted=" + isCompleted +
        ", priority=" + priority +
        '}';
  }
}
