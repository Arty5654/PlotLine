package com.plotline.backend.dto;

public class UserProfile {
  private String username;
  private String name;
  private String birthday;
  private String city;

  public UserProfile() {
  }

  public UserProfile(String username, String name, String birthday, String city) {
    this.username = username;
    this.name = name;
    this.birthday = birthday;
    this.city = city;
  }

  public String getUsername() {
    return username;
  }

  public void setUsername(String username) {
    this.username = username;
  }

  public String getName() {
    return name;
  }

  public void setName(String name) {
    this.name = name;
  }

  public String getBirthday() {
    return birthday;
  }

  public void setBirthday(String birthday) {
    this.birthday = birthday;
  }

  public String getCity() {
    return city;
  }

  public void setCity(String city) {
    this.city = city;
  }
  
}
