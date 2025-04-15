package com.plotline.backend.dto;

import java.util.List;

public class EventRequest {
  private String username;
  private String id;
  private String title;
  private String description;
  private String startDate; // or use a date/time type if desired
  private String endDate;
  private String eventType;
  private String recurrence;
  private List<String> invitedFriends;

  public EventRequest() {
  }

  public EventRequest(String username, String id, String title, String description, String startDate, String endDate, String eventType, String recurrence, List<String> invitedFriends) {
    this.username = username;
    this.id = id;
    this.title = title;
    this.description = description;
    this.startDate = startDate;
    this.endDate = endDate;
    this.eventType = eventType;
    this.recurrence = recurrence;
    this.invitedFriends = invitedFriends;
  }

  public String getUsername() {
    return username;
  }

  public void setUsername(String username) {
    this.username = username;
  }

  public String getId() {
    return id;
  }

  public void setId(String id) {
    this.id = id;
  }

  public String getTitle() {
    return title;
  }

  public void setTitle(String title) {
    this.title = title;
  }

  public String getDescription() {
    return description;
  }

  public void setDescription(String description) {
    this.description = description;
  }

  public String getStartDate() {
    return startDate;
  }

  public void setStartDate(String startDate) {
    this.startDate = startDate;
  }

  public String getEndDate() {
    return endDate;
  }

  public void setEndDate(String endDate) {
    this.endDate = endDate;
  }

  public String getEventType() {
    return eventType;
  }

  public void setEventType(String eventType) {
    this.eventType = eventType;
  }

  public String getRecurrence() {
    return recurrence;
  }

  public void setRecurrence(String recurrence) {
    this.recurrence = recurrence;
  }

  public List<String> getInvitedFriends() {
    return invitedFriends;
  }

  public void setInvitedFriends(List<String> invitedFriends) {
    this.invitedFriends = invitedFriends;
  }

}
