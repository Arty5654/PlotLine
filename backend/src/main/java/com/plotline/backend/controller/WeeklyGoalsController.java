package com.plotline.backend.controller;

import com.plotline.backend.service.S3Service;
import com.plotline.backend.service.WeeklyGoalsService;
import com.plotline.backend.service.FriendsFeedService;
import com.plotline.backend.service.LongTermGoalsService;
import com.plotline.backend.dto.FriendPost;
import com.plotline.backend.dto.LongTermGoal;
import com.plotline.backend.dto.TaskItem;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/goals")
@CrossOrigin(origins = "*") // Allow frontend requests
public class WeeklyGoalsController {

  @Autowired
  private FriendsFeedService friendsFeedService;

  private final LongTermGoalsService longTermGoalsService;
  private final WeeklyGoalsService weeklyGoalsService;
  private final S3Service s3Service;

  public WeeklyGoalsController(S3Service s3Service, WeeklyGoalsService weeklyGoalsService,
      LongTermGoalsService longTermGoalsService) {
    this.s3Service = s3Service;
    this.weeklyGoalsService = weeklyGoalsService;
    this.longTermGoalsService = longTermGoalsService;
  }

  @GetMapping("/{username}")
  public Map<String, Object> getWeeklyGoals(@PathVariable String username) throws IOException {
    return weeklyGoalsService.getWeeklyGoals(username);
  }

  @PostMapping("/{username}")
  public ResponseEntity<String> addGoal(@PathVariable String username, @RequestBody TaskItem newTask)
      throws IOException {
    boolean success = weeklyGoalsService.addGoalToS3(username, newTask);
    if (success) {
      return ResponseEntity.ok("Goal added successfully!");
    } else {
      return ResponseEntity.status(500).body("Failed to add goal.");
    }
  }

  @DeleteMapping("/{username}/{taskId}")
  public ResponseEntity<String> deleteGoal(@PathVariable String username, @PathVariable int taskId) throws IOException {
    boolean success = weeklyGoalsService.deleteGoalFromS3(username, taskId);
    if (success) {
      return ResponseEntity.ok("Goal deleted successfully!");
    } else {
      return ResponseEntity.status(500).body("Failed to delete goal.");
    }
  }

  @PutMapping("/{username}/{taskId}")
  public ResponseEntity<String> updateGoal(@PathVariable String username, @PathVariable int taskId,
      @RequestBody TaskItem updatedTask) throws IOException {
    boolean success = weeklyGoalsService.updateGoalInS3(username, taskId, updatedTask);
    if (success) {
      return ResponseEntity.ok("Goal updated successfully!");
    } else {
      return ResponseEntity.status(500).body("Failed to update goal.");
    }
  }

  @DeleteMapping("/{username}/reset")
  public ResponseEntity<String> resetGoals(@PathVariable String username) throws IOException {
    boolean success = weeklyGoalsService.resetGoalsInS3(username);
    if (success) {
      return ResponseEntity.ok("All goals have been reset!");
    } else {
      return ResponseEntity.status(500).body("Failed to reset goals.");
    }
  }

  @PutMapping("/{username}/{taskId}/completion")
  public ResponseEntity<String> updateGoalCompletion(
      @PathVariable String username,
      @PathVariable int taskId,
      @RequestBody Map<String, Boolean> request) throws IOException {
    boolean isCompleted = request.get("isCompleted");
    boolean success = weeklyGoalsService.updateGoalCompletionInS3(username, taskId, isCompleted);
    if (success) {
      return ResponseEntity.ok("Task completion updated successfully!");
    } else {
      return ResponseEntity.status(500).body("Failed to update task completion.");
    }
  }

  /* LONG TERM GOALS */

  @PostMapping("/{username}/long-term")
  public ResponseEntity<String> addLongTermGoal(@PathVariable String username, @RequestBody LongTermGoal newGoal) {
    boolean success = longTermGoalsService.addLongTermGoalToS3(username, newGoal);
    return success
        ? ResponseEntity.ok("Long-term goal added!")
        : ResponseEntity.status(500).body("Failed to add long-term goal.");
  }

  @GetMapping("/{username}/long-term")
  public Map<String, Object> getLongTermGoals(@PathVariable String username) {
    return longTermGoalsService.getLongTermGoals(username);
  }

  @PutMapping("/{username}/long-term/{goalId}/steps/{stepId}")
  public ResponseEntity<String> updateStepCompletion(
      @PathVariable String username,
      @PathVariable UUID goalId,
      @PathVariable UUID stepId,
      @RequestBody Map<String, Boolean> request) {

    boolean isCompleted = request.get("isCompleted");
    boolean success = longTermGoalsService.updateStepCompletionInS3(username, goalId, stepId, isCompleted);

    if (success) {
      return ResponseEntity.ok("Step completion updated successfully!");
    } else {
      return ResponseEntity.status(500).body("Failed to update step.");
    }
  }

  @DeleteMapping("/{username}/long-term/reset")
  public ResponseEntity<String> resetLongTermGoals(@PathVariable String username) throws IOException {
    boolean success = longTermGoalsService.resetLongTermGoalsInS3(username);
    if (success) {
      return ResponseEntity.ok("All long-term goals have been reset!");
    } else {
      return ResponseEntity.status(500).body("Failed to reset long-term goals.");
    }
  }

  @PutMapping("/{username}/long-term/{goalId}/archive")
  public ResponseEntity<String> archiveLongTermGoal(
      @PathVariable String username,
      @PathVariable UUID goalId) {

    boolean success = longTermGoalsService.archiveLongTermGoalInS3(username, goalId);
    if (success) {
      return ResponseEntity.ok("Goal archived successfully!");
    } else {
      return ResponseEntity.status(500).body("Failed to archive goal.");
    }
  }

  @PutMapping("/{username}/long-term/{goalId}/unarchive")
  public ResponseEntity<String> unarchiveLongTermGoal(
      @PathVariable String username,
      @PathVariable UUID goalId) {

    boolean success = longTermGoalsService.unarchiveLongTermGoalInS3(username, goalId);
    if (success) {
      return ResponseEntity.ok("Goal unarchived successfully!");
    } else {
      return ResponseEntity.status(500).body("Failed to unarchive goal.");
    }
  }

  // Friends Feed

  @PostMapping("/friends-feed/{username}/post")
  public ResponseEntity<String> postGoalToFriendsFeed(@PathVariable String username, @RequestBody FriendPost post) {
    boolean success = friendsFeedService.addPostToFeed(post);
    return success ? ResponseEntity.ok("Post shared successfully!")
        : ResponseEntity.status(500).body("Failed to share post.");
  }

  @GetMapping("/friends-feed/{username}")
  public ResponseEntity<List<FriendPost>> getFriendsFeed(@PathVariable String username) {
    List<FriendPost> feed = friendsFeedService.getFriendsFeed(username);
    return ResponseEntity.ok(feed);
  }

  @DeleteMapping("/friends-feed/{username}/post/{postId}")
  public ResponseEntity<String> deleteFriendPost(
      @PathVariable String username,
      @PathVariable UUID postId) {
    boolean success = friendsFeedService.deletePostById(username, postId);
    if (success) {
      return ResponseEntity.ok("Post deleted.");
    } else {
      return ResponseEntity.status(500).body("Failed to delete post.");
    }
  }

  @PutMapping("/friends-feed/{username}/post/{postId}/like")
  public ResponseEntity<String> toggleLikePost(
      @PathVariable String username,
      @PathVariable UUID postId) {
    boolean success = friendsFeedService.toggleLike(username, postId);
    return success ? ResponseEntity.ok("Toggled like.") : ResponseEntity.status(500).body("Error.");
  }

  @PostMapping("/friends-feed/{username}/post/{postId}/comment")
  public ResponseEntity<String> addCommentToPost(
      @PathVariable String username,
      @PathVariable UUID postId,
      @RequestBody Map<String, String> body) {
    String comment = body.get("comment");
    boolean success = friendsFeedService.addComment(username, postId, comment);
    return success ? ResponseEntity.ok("Comment added.") : ResponseEntity.status(500).body("Error.");
  }

}
