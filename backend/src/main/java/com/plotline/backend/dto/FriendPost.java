package com.plotline.backend.dto;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

public class FriendPost {
  private UUID id;
  private String username;
  private LongTermGoal goal;
  private String comment;
  private Set<String> likedBy = new HashSet<>(); // usernames of those who liked
  private List<String> comments = new ArrayList<>();

  // Getters and Setters

  public UUID getId() {
    return id;
  }

  public void setId(UUID id) {
    this.id = id;
  }

  public String getUsername() {
    return username;
  }

  public void setUsername(String username) {
    this.username = username;
  }

  public LongTermGoal getGoal() {
    return goal;
  }

  public void setGoal(LongTermGoal goal) {
    this.goal = goal;
  }

  public String getComment() {
    return comment;
  }

  public void setComment(String comment) {
    this.comment = comment;
  }

  public Set<String> getLikedBy() {
    return likedBy;
  }

  public void setLikedBy(Set<String> likedBy) {
    this.likedBy = likedBy;
  }

  public List<String> getComments() {
    return comments;
  }

  public void setComments(List<String> comments) {
    this.comments = comments;
  }

}
