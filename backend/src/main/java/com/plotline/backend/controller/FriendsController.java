package com.plotline.backend.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import com.plotline.backend.dto.FriendList;
import com.plotline.backend.dto.RequestList;
import com.plotline.backend.dto.FriendRequest;
import com.plotline.backend.security.ActingUser;
import com.plotline.backend.security.CurrentUser;
import com.plotline.backend.security.ForbiddenException;
import com.plotline.backend.service.FriendsService;


import static com.plotline.backend.util.UsernameUtils.normalize;

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
    @ActingUser(value = {}, others = {"senderUsername", "receiverUsername"})
    public ResponseEntity<String> createOrUpdateFriendRequest(@RequestBody FriendRequest friendRequest) throws Exception {
        String status = friendRequest.getStatus();
        boolean answering = "ACCEPTED".equalsIgnoreCase(status) || "DECLINED".equalsIgnoreCase(status);
        if (answering) {
            // only the person who received a request can answer it, and only if it really exists
            CurrentUser.check(friendRequest.getReceiverUsername());
            String sender = normalize(friendRequest.getSenderUsername());
            boolean pending = friendsService.getFriendRequests(CurrentUser.require()).getPendingRequests().stream()
                    .anyMatch(r -> normalize(r).equals(sender));
            if (!pending && "ACCEPTED".equalsIgnoreCase(status)) {
                throw new ForbiddenException("That friend request doesn't exist.");
            }
        } else {
            CurrentUser.check(friendRequest.getSenderUsername());
        }

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
    @ActingUser(value = {}, others = {"username"})
    public ResponseEntity<RequestList> getFriendRequests(@RequestParam String username) {
        try {
            RequestList requestList = friendsService.getFriendRequests(username);
            if (!CurrentUser.is(username)) {
                // someone else's requests: only reveal whether *you* have one pending with them
                String me = CurrentUser.require();
                requestList.setPendingRequests(requestList.getPendingRequests().stream()
                        .filter(r -> normalize(r).equals(me)).collect(java.util.stream.Collectors.toList()));
            }
            return ResponseEntity.ok(requestList);
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body(null);
        }
    }

    @PostMapping("/remove")
    @ActingUser(value = {}, others = {"senderUsername", "receiverUsername"})
    public ResponseEntity<String> removeFriend(@RequestBody FriendRequest friendRequest) {
        // you can only end a friendship you're part of
        if (!CurrentUser.is(friendRequest.getSenderUsername()) && !CurrentUser.is(friendRequest.getReceiverUsername())) {
            throw new ForbiddenException();
        }
        try {
            friendsService.removeFriend(friendRequest.getSenderUsername(), friendRequest.getReceiverUsername());
            return ResponseEntity.ok("Removed friend");
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body("Error removing friend");
        }
    }
}
