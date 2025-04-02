package com.plotline.backend.dto;

import java.util.UUID;

public class LongTermStep {
  private UUID id;
  private String name;
  private boolean isCompleted;

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
}
