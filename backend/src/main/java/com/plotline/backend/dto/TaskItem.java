package com.plotline.backend.dto;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.List;

@JsonIgnoreProperties(ignoreUnknown = true) // the app also sends fields only it uses
public class TaskItem {

  private int id;
  private String name;
  private boolean isCompleted;
  private Priority priority;
  private boolean notificationsEnabled;
  private String notificationType; // e.g., "dueDate", "priority", "custom"
  private LocalTime notificationTime; // optional for time-of-day reminders

  @JsonFormat(pattern = "yyyy-MM-dd")
  private LocalDate dueDate;

  private List<GoalReminder> reminders = new ArrayList<>();

  // set when this weekly goal is a step of a long-term goal (they're checked off together)
  private String longTermGoalId;
  private String longTermStepId;

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

  public List<GoalReminder> getReminders() {
    return reminders;
  }

  public void setReminders(List<GoalReminder> reminders) {
    this.reminders = reminders != null ? reminders : new ArrayList<>();
  }

  public String getLongTermGoalId() {
    return longTermGoalId;
  }

  public void setLongTermGoalId(String longTermGoalId) {
    this.longTermGoalId = longTermGoalId;
  }

  public String getLongTermStepId() {
    return longTermStepId;
  }

  public void setLongTermStepId(String longTermStepId) {
    this.longTermStepId = longTermStepId;
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
