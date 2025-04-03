package com.plotline.backend.dto;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.LocalDate;
import java.time.LocalDateTime;

public class TaskItem {

  private int id;
  private String name;
  private boolean isCompleted;
  private Priority priority;

  @JsonFormat(pattern = "yyyy-MM-dd")
  private LocalDate dueDate;

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

  public TaskItem(int id, String name, boolean isCompleted, Priority priority, LocalDate dueDate) {
    this.id = id;
    this.name = name;
    this.isCompleted = isCompleted;
    this.priority = priority;
    this.dueDate = dueDate;
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

  public LocalDate getDueDate() {
    return dueDate;
  }

  public void setDueDate(LocalDate dueDate) {
    this.dueDate = dueDate;
  }

  @Override
  public String toString() {
    return "TaskItem{" +
        "id=" + id +
        ", name='" + name + '\'' +
        ", isCompleted=" + isCompleted +
        ", priority=" + priority +
        ", dueDate=" + dueDate +
        '}';
  }
}
