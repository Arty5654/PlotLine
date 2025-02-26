package com.plotline.backend.controller;

import com.plotline.backend.service.S3Service;

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
  public Map<String, Object> getWeeklyGoals(@PathVariable String username) {
    return s3Service.getWeeklyGoals(username);
  }
}
