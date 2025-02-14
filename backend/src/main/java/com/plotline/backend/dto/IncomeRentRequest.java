package com.plotline.backend.dto;

public class IncomeRentRequest {
  private String username;
  private double income;
  private double rent;

  public String getUsername() {
    return username;
  }

  public void setUsername(String username) {
    this.username = username;
  }

  public double getIncome() {
    return income;
  }

  public void setIncome(double income) {
    this.income = income;
  }

  public double getRent() {
    return rent;
  }

  public void setRent(double rent) {
    this.rent = rent;
  }
  
}
