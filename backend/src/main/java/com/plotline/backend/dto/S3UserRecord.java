package com.plotline.backend.dto;

public class S3UserRecord {
    private String username;
    private String phone;
    private String password;
    private String birthday;
    private String city;
    
    public S3UserRecord() {
    }
    
    public S3UserRecord(String username, String phone, String password) {
        this.username = username;
        this.phone = phone;
        this.password = password;
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
}
