package com.plotline.backend.controller;

import com.plotline.backend.dto.SleepSchedule;
import com.plotline.backend.service.SleepScheduleService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;

@RestController
@RequestMapping("/api/health")
public class SleepScheduleController {

    @Autowired
    private SleepScheduleService sleepScheduleService;

    // Get sleep schedule for a user
    @GetMapping("/users/{username}/health-entries/sleep_schedule.json")
    public ResponseEntity<SleepSchedule> getSleepSchedule(@PathVariable String username) {
        try {
            SleepSchedule schedule = sleepScheduleService.getSleepSchedule(username);
            return ResponseEntity.ok(schedule);
        } catch (IOException e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body(null);
        }
    }

    // Update sleep schedule for a user
    @PutMapping("/users/{username}/health-entries/sleep_schedule.json")
    public ResponseEntity<String> updateSleepSchedule(
            @PathVariable String username,
            @RequestBody SleepSchedule sleepSchedule) {
        try {
            // Make sure the username in the path matches the one in the schedule
            sleepSchedule.setUsername(username);
            
            boolean success = sleepScheduleService.saveSleepSchedule(sleepSchedule);
            if (success) {
                return ResponseEntity.ok("Sleep schedule updated successfully");
            } else {
                return ResponseEntity.status(400).body("Failed to update sleep schedule");
            }
        } catch (IOException e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error updating sleep schedule: " + e.getMessage());
        }
    }
}