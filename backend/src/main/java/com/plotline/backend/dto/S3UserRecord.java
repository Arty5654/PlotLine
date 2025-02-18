package com.plotline.backend.dto;

public class S3UserRecord {
    private String username;
    private String phone;
    private String password;
    private Boolean isGoogle;
    private Boolean isVerified;
    
    public S3UserRecord() {
    }
    
    public S3UserRecord(String username, String phone, String password, Boolean isGoogle, Boolean isVerified) {
        this.username = username;
        this.phone = phone;
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
    
    public String getPhone() {
        return phone;
    }
    
    public void setPhone(String phone) {
        this.phone = phone;
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

    public Boolean getIsVerified() {
        return isVerified;
    }

    public void setIsVerified(Boolean isVerified) {
        this.isVerified = isVerified;
    }
}
