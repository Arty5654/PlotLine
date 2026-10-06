package com.plotline.backend.dto;

public class AppleSigninRequest {
    private String identityToken;
    private String rawNonce;
    // only sent when the server asked for it ("Username Required")
    private String username;
    // only sent when the server asked for it ("Link Required")
    private String linkPassword;

    public AppleSigninRequest() {
    }

    public AppleSigninRequest(String identityToken, String rawNonce, String username, String linkPassword) {
        this.identityToken = identityToken;
        this.rawNonce = rawNonce;
        this.username = username;
        this.linkPassword = linkPassword;
    }

    public String getIdentityToken() {
        return identityToken;
    }

    public void setIdentityToken(String identityToken) {
        this.identityToken = identityToken;
    }

    public String getRawNonce() {
        return rawNonce;
    }

    public void setRawNonce(String rawNonce) {
        this.rawNonce = rawNonce;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getLinkPassword() {
        return linkPassword;
    }

    public void setLinkPassword(String linkPassword) {
        this.linkPassword = linkPassword;
    }
}
