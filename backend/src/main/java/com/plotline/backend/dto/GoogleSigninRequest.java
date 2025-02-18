package com.plotline.backend.dto;

public class GoogleSigninRequest {
    private String idToken;
    private String username;

    public GoogleSigninRequest() {
    }

    public GoogleSigninRequest(String idToken, String username) {
        this.idToken = idToken;
        this.username = username;
    }

    public String getIdToken() {
        return idToken;
    }

    public void setIdToken(String idToken) {
        this.idToken = idToken;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }
}