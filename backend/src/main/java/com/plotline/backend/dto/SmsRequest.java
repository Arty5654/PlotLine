package com.plotline.backend.dto;

public class SmsRequest {
  private String toNumber;

  public SmsRequest() {
  }

  public SmsRequest(String toNumber) {
    this.toNumber = toNumber;
  }

  public String getToNumber() {
    return toNumber;
  }

  public void setToNumber(String toNumber) {
    this.toNumber = toNumber;
  }

  
}
