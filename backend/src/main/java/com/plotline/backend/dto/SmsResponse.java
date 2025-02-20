package com.plotline.backend.dto;

public class SmsResponse {
  private String message;
  private boolean success;

  public SmsResponse() {
  }

  public SmsResponse(String message, boolean success) {
    this.message = message;
    this.success = success;
  }

  public String getMessage() {
    return message;
  }

  public void setMessage(String message) {
    this.message = message;
  }

  public boolean isSuccess() {
    return success;
  }

  public void setSuccess(boolean success) {
    this.success = success;
  }
  
}
