package com.plotline.backend.dto;

public class AuthResponse {
    private boolean success;
    private String token;
    private String error;
    private String displayUsername;

    public AuthResponse() {
    }

    public AuthResponse(boolean success, String token, String error) {
        this.success = success;
        this.token = token;
        this.error = error;
    }

    public AuthResponse(boolean success, String token, String error, String displayUsername) {
        this.success = success;
        this.token = token;
        this.error = error;
        this.displayUsername = displayUsername;
    }
    
    public String getToken() {
        return token;
    }
    
    public void setToken(String token) {
        this.token = token;
    }

    public boolean isSuccess() {
        return success;
    }

    public void setSuccess(boolean success) {
        this.success = success;
    }

    public String getError() {
        return error;
    }

    public void setError(String error) {
        this.error = error;
    }

    public String getDisplayUsername() {
        return displayUsername;
    }

    public void setDisplayUsername(String displayUsername) {
        this.displayUsername = displayUsername;
    }

}
