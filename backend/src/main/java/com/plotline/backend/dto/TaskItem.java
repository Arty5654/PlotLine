package com.plotline.backend.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

public class TaskItem {
  private int id;
  private String name;
  private boolean isCompleted;

  // Default Constructor (required for JSON deserialization)
  public TaskItem() {
  }

  public TaskItem(@JsonProperty("id") int id,
      @JsonProperty("name") String name,
      @JsonProperty("isCompleted") boolean isCompleted) {
    this.id = id;
    this.name = name;
    this.isCompleted = isCompleted;
  }

  // Getters & Setters
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

  @Override
  public String toString() {
    return "TaskItem{" +
        "id=" + id +
        ", name='" + name + '\'' +
        ", isCompleted=" + isCompleted +
        '}';
  }
}
