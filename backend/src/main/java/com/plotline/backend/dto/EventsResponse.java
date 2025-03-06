package com.plotline.backend.dto;

import java.util.List;

public class EventsResponse {
  
  private boolean success;
  private String error;
  private List<EventDto> events;

  public EventsResponse() {
  }

  public EventsResponse(boolean success, String error, List<EventDto> events) {
    this.success = success;
    this.error = error;
    this.events = events;
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

  public List<EventDto> getEvents() {
    return events;
  }

  public void setEvents(List<EventDto> events) {
    this.events = events;
  }
}
