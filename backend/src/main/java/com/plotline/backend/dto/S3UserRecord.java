package com.plotline.backend.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

@JsonIgnoreProperties(ignoreUnknown = true)
public class S3UserRecord {
    private String username;
    private String displayUsername; // Original case-sensitive username from signup
    private String phone;
    private String email;
    private String password;
    private Boolean isGoogle;
    private Boolean isApple;
    private Boolean isVerified;
    // stable account ids from Google / Apple, used to recognize returning social sign-ins
    private String googleSub;
    private String appleSub;
    // epoch millis; login tokens issued before this belong to an older account with the same name
    private Long createdAt;
    // which Terms of Service / Privacy Policy version the user agreed to, and when (epoch millis)
    private String termsVersion;
    private Long termsAcceptedAt;

    public S3UserRecord() {
    }

    public S3UserRecord(String username, String displayUsername, String phone, String email, String password, Boolean isGoogle, Boolean isVerified) {
        this.username = username;
        this.displayUsername = displayUsername;
        this.phone = phone;
        this.email = email;
        this.password = password;
        this.isGoogle = isGoogle;
        this.isVerified = isVerified;
    }
    
    public String getUsername() {
        return username;
    }
    
    public void setUsername(String username) {
        this.username = username;
    }

    public String getDisplayUsername() {
        return displayUsername;
    }

    public void setDisplayUsername(String displayUsername) {
        this.displayUsername = displayUsername;
    }

    public String getPhone() {
        return phone;
    }
    
    public void setPhone(String phone) {
        this.phone = phone;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }
    
    public String getPassword() {
        return password;
    }
    
    public void setPassword(String password) {
        this.password = password;
    }

    public Boolean getIsGoogle() {
        return isGoogle;
    }

    public void setIsGoogle(Boolean isGoogle) {
        this.isGoogle = isGoogle;
    }

    public Boolean getIsApple() {
        return isApple;
    }

    public void setIsApple(Boolean isApple) {
        this.isApple = isApple;
    }

    public String getGoogleSub() {
        return googleSub;
    }

    public void setGoogleSub(String googleSub) {
        this.googleSub = googleSub;
    }

    public String getAppleSub() {
        return appleSub;
    }

    public void setAppleSub(String appleSub) {
        this.appleSub = appleSub;
    }

    public String getTermsVersion() {
        return termsVersion;
    }

    public void setTermsVersion(String termsVersion) {
        this.termsVersion = termsVersion;
    }

    public Long getTermsAcceptedAt() {
        return termsAcceptedAt;
    }

    public void setTermsAcceptedAt(Long termsAcceptedAt) {
        this.termsAcceptedAt = termsAcceptedAt;
    }

    public Long getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Long createdAt) {
        this.createdAt = createdAt;
    }

    public Boolean getIsVerified() {
        return isVerified;
    }

    public void setIsVerified(Boolean isVerified) {
        this.isVerified = isVerified;
    }
}
