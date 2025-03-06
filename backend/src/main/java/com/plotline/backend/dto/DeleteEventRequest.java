package com.plotline.backend.dto;

public class DeleteEventRequest {
  
  private String username;
  private String eventId;

  public DeleteEventRequest() {
  }

  public DeleteEventRequest(String username, String eventId) {
    this.username = username;
    this.eventId = eventId;
  }

  public String getUsername() {
    return username;
  }

  public void setUsername(String username) {
    this.username = username;
  }

  public String getEventId() {
    return eventId;
  }

  public void setEventId(String eventId) {
    this.eventId = eventId;
  }
  
}
