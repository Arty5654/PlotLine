package com.plotline.backend.controller;


import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.plotline.backend.dto.UserProfile;
import com.plotline.backend.service.UserProfileService;


@RestController
@RequestMapping("/profile")
public class ProfileController {
  
    @Autowired
    private final UserProfileService userProfileService;
    public ProfileController(UserProfileService userProfileService) {
        this.userProfileService = userProfileService;
    }

    @PutMapping("/save-user")
    public ResponseEntity<String> saveProfile(@RequestBody UserProfile profile) {
        userProfileService.saveProfile(profile);
        return ResponseEntity.ok("Profile saved successfully");

    }

    @GetMapping("/get-user")
    public ResponseEntity<UserProfile> getProfile(@RequestParam String username) {
        UserProfile profile = userProfileService.getProfile(username);

        if (profile == null) {
            System.out.println("Profile not found");
            return ResponseEntity.badRequest().body(null);
        }

        return ResponseEntity.ok(profile);
    }

    @PostMapping("/upload-profile-pic")
    public ResponseEntity<String> uploadProfilePicture(@RequestParam("file") MultipartFile file,
                                                       @RequestParam("username") String username) {

        try {
            String imageUrl = userProfileService.uploadProfilePicture(file, username);
            return ResponseEntity.ok(imageUrl);
        } catch (Exception e) {
            return ResponseEntity.status(500).body("Error uploading profile picture");
        }
    }
}
