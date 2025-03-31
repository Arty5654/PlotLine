package com.plotline.backend.dto;

public class FriendRequest {
    private String senderUsername;
    private String receiverUsername;
    private String status; // can be either: "PENDING", "ACCEPTED", "DECLINED"

    public FriendRequest() { 
    }

    public FriendRequest(String senderUsername, String receiverUsername, String status) {
        this.senderUsername = senderUsername;
        this.receiverUsername = receiverUsername;
        this.status = status;
    }

    public String getSenderUsername() {
        return senderUsername;
    }
    public void setSenderUsername(String senderUsername) {
        this.senderUsername = senderUsername;
    }
    public String getReceiverUsername() {
        return receiverUsername;
    }
    public void setReceiverUsername(String receiverUsername) {
        this.receiverUsername = receiverUsername;
    }
    public String getStatus() {
        return status;
    }
    public void setStatus(String status) {
        this.status = status;
    }
}

