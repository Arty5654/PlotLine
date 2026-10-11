package com.plotline.backend.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/** A weekly goal as shown in the friends feed (a snapshot taken when it was shared). */
@JsonIgnoreProperties(ignoreUnknown = true)
public class WeeklyGoalShare {
  private String name;
  private String priority;
  private String dueDate; // "yyyy-MM-dd", optional
  private boolean completed;

  public WeeklyGoalShare() {
  }

  public String getName() { return name; }
  public void setName(String name) { this.name = name; }

  public String getPriority() { return priority; }
  public void setPriority(String priority) { this.priority = priority; }

  public String getDueDate() { return dueDate; }
  public void setDueDate(String dueDate) { this.dueDate = dueDate; }

  public boolean isCompleted() { return completed; }
  public void setCompleted(boolean completed) { this.completed = completed; }
}
