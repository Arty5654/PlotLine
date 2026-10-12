package com.plotline.backend.dto;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class EventDto {
    private String id;
    private String title;
    private String description;
    private String location; // "Starbucks, 123 Main St" (optional)
    // repeating: an imported rule ("FREQ=WEEKLY;BYDAY=MO,WE"), the last day ("2026-12-31"), and dates
    // taken out of the series ("2026-10-12": changed or deleted on their own)
    private String recurrenceRule;
    private String recurrenceEnd;
    private List<String> excludedDates = new java.util.ArrayList<>();
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

    public String getLocation() {
        return location;
    }

    public void setLocation(String location) {
        this.location = location;
    }

    public String getRecurrenceRule() {
        return recurrenceRule;
    }

    public void setRecurrenceRule(String recurrenceRule) {
        this.recurrenceRule = recurrenceRule;
    }

    public String getRecurrenceEnd() {
        return recurrenceEnd;
    }

    public void setRecurrenceEnd(String recurrenceEnd) {
        this.recurrenceEnd = recurrenceEnd;
    }

    public List<String> getExcludedDates() {
        return excludedDates;
    }

    public void setExcludedDates(List<String> excludedDates) {
        this.excludedDates = excludedDates == null ? new java.util.ArrayList<>() : excludedDates;
    }

    /** the place and how it repeats, e.g. onto an invited friend's copy */
    public void copyDetailsFrom(EventDto other) {
        this.location = other.location;
        this.recurrenceRule = other.recurrenceRule;
        this.recurrenceEnd = other.recurrenceEnd;
        this.excludedDates = new java.util.ArrayList<>(other.getExcludedDates());
    }

    /** same title, time, place and repeat (what an import can change) */
    public boolean sameDetails(EventDto other) {
        return java.util.Objects.equals(title, other.title) && java.util.Objects.equals(description, other.description)
                && java.util.Objects.equals(startDate, other.startDate) && java.util.Objects.equals(endDate, other.endDate)
                && java.util.Objects.equals(location, other.location) && java.util.Objects.equals(recurrence, other.recurrence)
                && java.util.Objects.equals(recurrenceRule, other.recurrenceRule)
                && java.util.Objects.equals(recurrenceEnd, other.recurrenceEnd)
                && java.util.Objects.equals(getExcludedDates(), other.getExcludedDates());
    }
}
