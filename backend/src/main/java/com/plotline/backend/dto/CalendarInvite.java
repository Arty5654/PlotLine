package com.plotline.backend.dto;

public class CalendarInvite {
    private String id;
    private String fromUsername;
    private String toUsername;
    private String level; // "view" or "add"
    private boolean requireApproval;
    private String sentAt;

    public CalendarInvite() {}

    public CalendarInvite(String id, String fromUsername, String toUsername, String level, boolean requireApproval, String sentAt) {
        this.id = id;
        this.fromUsername = fromUsername;
        this.toUsername = toUsername;
        this.level = level;
        this.requireApproval = requireApproval;
        this.sentAt = sentAt;
    }

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getFromUsername() { return fromUsername; }
    public void setFromUsername(String fromUsername) { this.fromUsername = fromUsername; }

    public String getToUsername() { return toUsername; }
    public void setToUsername(String toUsername) { this.toUsername = toUsername; }

    public String getLevel() { return level; }
    public void setLevel(String level) { this.level = level; }

    public boolean isRequireApproval() { return requireApproval; }
    public void setRequireApproval(boolean requireApproval) { this.requireApproval = requireApproval; }

    public String getSentAt() { return sentAt; }
    public void setSentAt(String sentAt) { this.sentAt = sentAt; }
}
