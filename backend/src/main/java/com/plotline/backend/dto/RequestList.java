package com.plotline.backend.dto;

import java.util.ArrayList;
import java.util.List;

public class RequestList {
    private String username;
    private List<String> pendingRequests;

    public RequestList() {
      this.pendingRequests= new ArrayList<String>();
    }

    public RequestList(String username, List<String> pendingRequests) {
        this.username = username;
        this.pendingRequests = pendingRequests;
    }

    public String getUsername() {
        return username;
    }
    public void setUsername(String username) {
        this.username = username;
    }
    public List<String> getPendingRequests() {
        return pendingRequests;
    }
    public void setPendingRequests(List<String> pendingRequests) {
        this.pendingRequests = pendingRequests;
    }
}

