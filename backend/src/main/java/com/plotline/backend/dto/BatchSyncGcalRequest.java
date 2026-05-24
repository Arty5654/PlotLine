package com.plotline.backend.dto;

import java.util.List;

public class BatchSyncGcalRequest {
    private String username;
    private List<EventDto> events;

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public List<EventDto> getEvents() { return events; }
    public void setEvents(List<EventDto> events) { this.events = events; }
}
