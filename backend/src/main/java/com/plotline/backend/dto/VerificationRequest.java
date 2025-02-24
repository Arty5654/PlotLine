package com.plotline.backend.dto;

public class VerificationRequest {
  private String phoneNumber;
  private String code;
  private String username;

  public VerificationRequest() {
  }

  public VerificationRequest(String phoneNumber, String code, String username) {
    this.phoneNumber = phoneNumber;
    this.code = code;
    this.username = username;
  }

  public String getPhoneNumber() {
    return phoneNumber;
  }

  public void setPhoneNumber(String phoneNumber) {
    this.phoneNumber = phoneNumber;
  }

  public String getCode() {
    return code;
  }

  public void setCode(String code) {
    this.code = code;
  }

  public String getUsername() {
    return username;
  }

  public void setUsername(String username) {
    this.username = username;
  }
  
}
