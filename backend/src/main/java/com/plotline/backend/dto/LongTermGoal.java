package com.plotline.backend.dto;

import java.util.List;
import java.util.UUID;

public class LongTermGoal {
  private UUID id;
  private String title;
  private List<LongTermStep> steps;

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
}
