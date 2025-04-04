package com.plotline.backend.controller;

import com.plotline.backend.service.S3Service;
import com.plotline.backend.dto.LongTermGoal;
import com.plotline.backend.dto.TaskItem;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.io.IOException;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/goals")
@CrossOrigin(origins = "*") // Allow frontend requests
public class WeeklyGoalsController {

  private final S3Service s3Service;

  public WeeklyGoalsController(S3Service s3Service) {
    this.s3Service = s3Service;
  }

  @GetMapping("/{username}")
  public Map<String, Object> getWeeklyGoals(@PathVariable String username) throws IOException {
    return s3Service.getWeeklyGoals(username);
  }

  @PostMapping("/{username}")
  public ResponseEntity<String> addGoal(@PathVariable String username, @RequestBody TaskItem newTask)
      throws IOException {
    boolean success = s3Service.addGoalToS3(username, newTask);
    if (success) {
      return ResponseEntity.ok("Goal added successfully!");
    } else {
      return ResponseEntity.status(500).body("Failed to add goal.");
    }
  }

  @DeleteMapping("/{username}/{taskId}")
  public ResponseEntity<String> deleteGoal(@PathVariable String username, @PathVariable int taskId) throws IOException {
    boolean success = s3Service.deleteGoalFromS3(username, taskId);
    if (success) {
      return ResponseEntity.ok("Goal deleted successfully!");
    } else {
      return ResponseEntity.status(500).body("Failed to delete goal.");
    }
  }

  @PutMapping("/{username}/{taskId}")
  public ResponseEntity<String> updateGoal(@PathVariable String username, @PathVariable int taskId,
      @RequestBody TaskItem updatedTask) throws IOException {
    boolean success = s3Service.updateGoalInS3(username, taskId, updatedTask);
    if (success) {
      return ResponseEntity.ok("Goal updated successfully!");
    } else {
      return ResponseEntity.status(500).body("Failed to update goal.");
    }
  }

  @DeleteMapping("/{username}/reset")
  public ResponseEntity<String> resetGoals(@PathVariable String username) throws IOException {
    boolean success = s3Service.resetGoalsInS3(username);
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
    boolean success = s3Service.updateGoalCompletionInS3(username, taskId, isCompleted);
    if (success) {
      return ResponseEntity.ok("Task completion updated successfully!");
    } else {
      return ResponseEntity.status(500).body("Failed to update task completion.");
    }
  }

  @PostMapping("/{username}/long-term")
  public ResponseEntity<String> addLongTermGoal(@PathVariable String username, @RequestBody LongTermGoal newGoal) {
    boolean success = s3Service.addLongTermGoalToS3(username, newGoal);
    return success
        ? ResponseEntity.ok("Long-term goal added!")
        : ResponseEntity.status(500).body("Failed to add long-term goal.");
  }

  @GetMapping("/{username}/long-term")
  public Map<String, Object> getLongTermGoals(@PathVariable String username) {
    return s3Service.getLongTermGoals(username);
  }

  @PutMapping("/{username}/long-term/{goalId}/steps/{stepId}")
  public ResponseEntity<String> updateStepCompletion(
      @PathVariable String username,
      @PathVariable UUID goalId,
      @PathVariable UUID stepId,
      @RequestBody Map<String, Boolean> request) {

    boolean isCompleted = request.get("isCompleted");
    boolean success = s3Service.updateStepCompletionInS3(username, goalId, stepId, isCompleted);

    if (success) {
      return ResponseEntity.ok("Step completion updated successfully!");
    } else {
      return ResponseEntity.status(500).body("Failed to update step.");
    }
  }

  @DeleteMapping("/{username}/long-term/reset")
  public ResponseEntity<String> resetLongTermGoals(@PathVariable String username) throws IOException {
    boolean success = s3Service.resetLongTermGoalsInS3(username);
    if (success) {
      return ResponseEntity.ok("All long-term goals have been reset!");
    } else {
      return ResponseEntity.status(500).body("Failed to reset long-term goals.");
    }
  }

}
