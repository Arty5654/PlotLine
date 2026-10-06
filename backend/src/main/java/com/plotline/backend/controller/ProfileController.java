package com.plotline.backend.controller;


import java.util.Collections;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.plotline.backend.dto.Trophy;
import com.plotline.backend.dto.UserProfile;
import com.plotline.backend.security.ActingUser;
import com.plotline.backend.security.CurrentUser;
import com.plotline.backend.service.FriendsService;
import com.plotline.backend.service.UserProfileService;

import static com.plotline.backend.util.UsernameUtils.normalize;


@RestController
@RequestMapping("/profile")
public class ProfileController {
  
    @Autowired
    private final UserProfileService userProfileService;
    private final FriendsService friendsService;
    public ProfileController(UserProfileService userProfileService, FriendsService friendsService) {
        this.userProfileService = userProfileService;
        this.friendsService = friendsService;
    }

    @PutMapping("/save-user")
    public ResponseEntity<String> saveProfile(@RequestBody UserProfile profile) {
        userProfileService.saveProfile(profile);
        return ResponseEntity.ok("Profile saved successfully");

    }

    // name, birthday and city are only shown to the user and their friends
    @GetMapping("/get-user")
    @ActingUser(value = {}, others = {"username"})
    public ResponseEntity<UserProfile> getProfile(@RequestParam String username) {
        UserProfile profile = userProfileService.getProfile(username);

        if (profile == null) {
            System.out.println("Profile not found");
            return ResponseEntity.badRequest().body(null);
        }

        if (!CurrentUser.is(username) && !isFriend(username)) {
            UserProfile limited = new UserProfile();
            limited.setUsername(profile.getUsername() != null ? profile.getUsername() : username);
            return ResponseEntity.ok(limited);
        }

        return ResponseEntity.ok(profile);
    }

    private boolean isFriend(String username) {
        try {
            return friendsService.getFriendList(CurrentUser.require()).getFriends().stream()
                    .anyMatch(f -> normalize(f).equals(normalize(username)));
        } catch (Exception e) {
            return false;
        }
    }

    @GetMapping("/get-phone")
    public ResponseEntity<String> getPhone(@RequestParam String username) {
        String phone = userProfileService.getPhoneNum(username);

        if (phone == null) {
            System.out.println("acc not found");
            return ResponseEntity.badRequest().body(null);
        }

        return ResponseEntity.ok(phone);
    }

    @PostMapping("/upload-profile-pic")
    public ResponseEntity<String> uploadProfilePicture(@RequestParam("file") MultipartFile file,
                                                       @RequestParam("username") String username) {

        System.out.println("Upload request triggered");

        try {
            String imageUrl = userProfileService.uploadProfilePicture(file, username);
            return ResponseEntity.ok(imageUrl);
        } catch (Exception e) {
            return ResponseEntity.status(500).body("Error uploading profile picture");
        }
    }

    @GetMapping("/get-profile-pic")
    @ActingUser(value = {}, others = {"username"}) // pictures are public
    public ResponseEntity<Map<String, String>> getProfilePicture(@RequestParam String username) {   
        String s3Url = "https://plotline-database-bucket.s3.amazonaws.com/users/" + username + "/profile_pictures/" + username + ".jpg";
        return ResponseEntity.ok(Collections.singletonMap("profilePicUrl", s3Url));
    }

    // TROPHY ENDPOINTS 

    @GetMapping("/get-trophies")
    @ActingUser(value = {}, others = {"username"}) // trophies are public
    public List<Trophy> getUserTrophies(@RequestParam String username) throws Exception {
        return userProfileService.getTrophies(username);
    }

    @PostMapping("/increment-trophies")
    public List<Trophy> incrementTrophy(
        @RequestParam String username,
        @RequestParam String trophyId,
        @RequestParam int amount
    ) throws Exception {
        return userProfileService.incrementTrophy(username, trophyId, amount);
    }

    @PostMapping("/create-default-trophies")
    public List<Trophy> createDefaultTrophies(
        @RequestParam String username
    ) throws Exception {
        return userProfileService.createDefaultTrophies(username);
    }



}
