package com.plotline.backend.dto;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class EventDto {
    private String id;
    private String title;
    private String description;
    private String startDate; // stored as string
    private String endDate;   // stored as string
    private String eventType;
    private String recurrence;
    private List<String> invitedFriends;
    private boolean friendsCanSee = true;
    private String addedBy = null;
    private String status = "approved";    // "approved", "pending", "invite-pending", "accepted", "declined"
    private Map<String, String> inviteStatuses = new HashMap<>(); // friend -> "pending"/"accepted"/"declined"

    // No-arg constructor needed for Jackson
    public EventDto() {}

    public EventDto(String id, String title, String description, String startDate, String endDate, String eventType, String recurrence, List<String> invitedFriends) {
        this.id = id;
        this.title = title;
        this.description = description;
        this.startDate = startDate;
        this.endDate = endDate;
        this.eventType = eventType;
        this.recurrence = recurrence;
        this.invitedFriends = invitedFriends;
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

    public boolean isFriendsCanSee() { return friendsCanSee; }
    public void setFriendsCanSee(boolean friendsCanSee) { this.friendsCanSee = friendsCanSee; }

    public String getAddedBy() { return addedBy; }
    public void setAddedBy(String addedBy) { this.addedBy = addedBy; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public Map<String, String> getInviteStatuses() { return inviteStatuses; }
    public void setInviteStatuses(Map<String, String> inviteStatuses) { this.inviteStatuses = inviteStatuses; }
}

