package com.plotline.backend.controller;

import com.plotline.backend.service.S3Service;
import com.plotline.backend.dto.TaskItem;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.io.IOException;
import java.util.Map;

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

}
