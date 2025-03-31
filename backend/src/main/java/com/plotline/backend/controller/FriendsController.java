package com.plotline.backend.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import com.plotline.backend.dto.FriendList;
import com.plotline.backend.dto.RequestList;
import com.plotline.backend.dto.FriendRequest;
import com.plotline.backend.service.FriendsService;

@RestController
@RequestMapping("/friends")
public class FriendsController {

    @Autowired
    private final FriendsService friendsService;

    public FriendsController(FriendsService friendsService) {
        this.friendsService = friendsService;
    }

    /**
     * Create or update a friend request.
     * When the status is "ACCEPTED" or "DECLINED" in the payload,
     * the service will handle it accordingly.
     */
    @PutMapping("/request")
    public ResponseEntity<String> createOrUpdateFriendRequest(@RequestBody FriendRequest friendRequest) {
        try {
            String response = friendsService.createOrUpdateFriendRequest(friendRequest);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error processing friend request");
        }
    }

    @GetMapping("/get-friends")
    public ResponseEntity<FriendList> getFriendList(@RequestParam String username) {
        try {
            FriendList friendList = friendsService.getFriendList(username);
            return ResponseEntity.ok(friendList);
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body(null);
        }
    }

    @GetMapping("/get-friend-requests")
    public ResponseEntity<RequestList> getFriendRequests(@RequestParam String username) {
        try {
            RequestList requestList = friendsService.getFriendRequests(username);
            return ResponseEntity.ok(requestList);
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body(null);
        }
    }
}

