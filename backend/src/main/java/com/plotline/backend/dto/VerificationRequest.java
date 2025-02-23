package com.plotline.backend.dto;

public class VerificationRequest {
  private String phoneNumber;
  private String code;

  public VerificationRequest() {
  }

  public VerificationRequest(String phoneNumber, String code) {
    this.phoneNumber = phoneNumber;
    this.code = code;
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
  
}
