package com.plotline.backend.dto;

public class EventResponse {
  
  private boolean success;
  private String error;
  private EventDto event;

  public EventResponse() {
  }

  public EventResponse(boolean success, String error, EventDto event) {
    this.success = success;
    this.error = error;
    this.event = event;
  }

  public boolean isSuccess() {
    return success;
  }

  public void setSuccess(boolean success) {
    this.success = success;
  }

  public String getError() {
    return error;
  }

  public void setError(String error) {
    this.error = error;
  }

  public EventDto getEvent() {
    return event;
  }

  public void setEvent(EventDto event) {
    this.event = event;
  }
  
}
