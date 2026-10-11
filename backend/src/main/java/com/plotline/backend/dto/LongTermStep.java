package com.plotline.backend.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import java.util.UUID;

@JsonIgnoreProperties(ignoreUnknown = true)
public class LongTermStep {
  private UUID id;
  private String name;
  private boolean isCompleted;
  private Integer weeklyGoalId; // set while this step is also a weekly goal (they're checked off together)

  public LongTermStep() {
  }

  public LongTermStep(UUID id, String name, boolean isCompleted) {
    this.id = id;
    this.name = name;
    this.isCompleted = isCompleted;
  }

  public UUID getId() {
    return id;
  }

  public void setId(UUID id) {
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

  public Integer getWeeklyGoalId() {
    return weeklyGoalId;
  }

  public void setWeeklyGoalId(Integer weeklyGoalId) {
    this.weeklyGoalId = weeklyGoalId;
  }
}
