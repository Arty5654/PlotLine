package com.plotline.backend.dto;

public class SavedPortfolio {
    private String username;
    private String content;

    public SavedPortfolio() {}

    public SavedPortfolio(String username, String content) {
        this.username = username;
        this.content = content;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }
}
