package com.plotline.backend.dto;

public class GoogleSigninRequest {
    private String idToken;
    private String email;

    public GoogleSigninRequest() {
    }

    public GoogleSigninRequest(String idToken, String email) {
        this.idToken = idToken;
        this.email = email;
    }

    public String getIdToken() {
        return idToken;
    }

    public void setIdToken(String idToken) {
        this.idToken = idToken;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }
}