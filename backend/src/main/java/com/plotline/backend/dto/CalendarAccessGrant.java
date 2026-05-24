package com.plotline.backend.dto;

public class CalendarAccessGrant {
    private String friendUsername;
    private String level; // "view" or "add"
    private boolean requireApproval;
    private String grantedAt;

    public CalendarAccessGrant() {}

    public CalendarAccessGrant(String friendUsername, String level, boolean requireApproval, String grantedAt) {
        this.friendUsername = friendUsername;
        this.level = level;
        this.requireApproval = requireApproval;
        this.grantedAt = grantedAt;
    }

    public String getFriendUsername() { return friendUsername; }
    public void setFriendUsername(String friendUsername) { this.friendUsername = friendUsername; }

    public String getLevel() { return level; }
    public void setLevel(String level) { this.level = level; }

    public boolean isRequireApproval() { return requireApproval; }
    public void setRequireApproval(boolean requireApproval) { this.requireApproval = requireApproval; }

    public String getGrantedAt() { return grantedAt; }
    public void setGrantedAt(String grantedAt) { this.grantedAt = grantedAt; }
}
