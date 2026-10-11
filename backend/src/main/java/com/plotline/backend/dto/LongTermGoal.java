package com.plotline.backend.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@JsonIgnoreProperties(ignoreUnknown = true)
public class LongTermGoal {
  private UUID id;
  private String title;
  private List<LongTermStep> steps;
  private String targetDate; // "yyyy-MM-dd", optional
  private List<GoalReminder> reminders = new ArrayList<>(); // relative ones follow targetDate

  public LongTermGoal() {
  }

  public LongTermGoal(UUID id, String title, List<LongTermStep> steps) {
    this.id = id;
    this.title = title;
    this.steps = steps;
  }

  public UUID getId() {
    return id;
  }

  public void setId(UUID id) {
    this.id = id;
  }

  public String getTitle() {
    return title;
  }

  public void setTitle(String title) {
    this.title = title;
  }

  public List<LongTermStep> getSteps() {
    return steps;
  }

  public void setSteps(List<LongTermStep> steps) {
    this.steps = steps;
  }

  public String getTargetDate() {
    return targetDate;
  }

  public void setTargetDate(String targetDate) {
    this.targetDate = targetDate;
  }

  public List<GoalReminder> getReminders() {
    return reminders;
  }

  public void setReminders(List<GoalReminder> reminders) {
    this.reminders = reminders != null ? reminders : new ArrayList<>();
  }
}
