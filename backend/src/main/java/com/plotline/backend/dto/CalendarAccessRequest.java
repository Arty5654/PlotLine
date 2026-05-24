package com.plotline.backend.dto;

public class CalendarAccessRequest {
    private String fromUsername;
    private String toUsername;
    private String recipientUsername;
    private String ownerUsername;
    private String friendUsername;
    private String inviteId;
    private String eventId;
    private String level;
    private boolean requireApproval;
    private boolean accept;
    private boolean keepEvents;

    public CalendarAccessRequest() {}

    public String getFromUsername() { return fromUsername; }
    public void setFromUsername(String fromUsername) { this.fromUsername = fromUsername; }

    public String getToUsername() { return toUsername; }
    public void setToUsername(String toUsername) { this.toUsername = toUsername; }

    public String getRecipientUsername() { return recipientUsername; }
    public void setRecipientUsername(String recipientUsername) { this.recipientUsername = recipientUsername; }

    public String getOwnerUsername() { return ownerUsername; }
    public void setOwnerUsername(String ownerUsername) { this.ownerUsername = ownerUsername; }

    public String getFriendUsername() { return friendUsername; }
    public void setFriendUsername(String friendUsername) { this.friendUsername = friendUsername; }

    public String getInviteId() { return inviteId; }
    public void setInviteId(String inviteId) { this.inviteId = inviteId; }

    public String getEventId() { return eventId; }
    public void setEventId(String eventId) { this.eventId = eventId; }

    public String getLevel() { return level; }
    public void setLevel(String level) { this.level = level; }

    public boolean isRequireApproval() { return requireApproval; }
    public void setRequireApproval(boolean requireApproval) { this.requireApproval = requireApproval; }

    public boolean isAccept() { return accept; }
    public void setAccept(boolean accept) { this.accept = accept; }

    public boolean isKeepEvents() { return keepEvents; }
    public void setKeepEvents(boolean keepEvents) { this.keepEvents = keepEvents; }
}
