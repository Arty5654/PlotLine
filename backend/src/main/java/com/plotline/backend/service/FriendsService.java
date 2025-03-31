package com.plotline.backend.service;

import com.plotline.backend.dto.FriendList;
import com.plotline.backend.dto.FriendRequest;
import com.plotline.backend.dto.RequestList;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.core.sync.RequestBody;

@Service
public class FriendsService {

    private final S3Client s3Client;
    private final String bucketName = "plotline-database-bucket";
    private final ObjectMapper objectMapper;

    public FriendsService(S3Client s3Client) {
        this.s3Client = s3Client;
        this.objectMapper = new ObjectMapper();
    }

    // read json from s3
    private <T> T readJson(String key, Class<T> clazz) {
        try {
            GetObjectRequest getRequest = GetObjectRequest.builder()
                    .bucket(bucketName)
                    .key(key)
                    .build();

            ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
            String json = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

            return objectMapper.readValue(json, clazz);
        } catch (Exception e) {
            return null;
        }
    }

    // write json back to s3
    private void writeJson(String key, Object object) throws Exception {
        String jsonData = objectMapper.writeValueAsString(object);

        PutObjectRequest putRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .contentType("application/json")
                .build();

        s3Client.putObject(putRequest, RequestBody.fromString(jsonData));
    }

    // add sender username to receivers friends list
    public String createOrUpdateFriendRequest(FriendRequest request) throws Exception {

        // update existing (accepted or declined) friend requests
        String status = request.getStatus();
        if ("ACCEPTED".equalsIgnoreCase(status)) {
            acceptFriendRequest(request);
            return "Accepted";
        } else if ("DECLINED".equalsIgnoreCase(status)) {
            declineFriendRequest(request);
            return "Declined";
        }

        String fKey = "users/" + request.getReceiverUsername() + "/friends.json"; // friends ket
        String key = "users/" + request.getReceiverUsername() + "/friend_requests.json"; // requests key

        FriendList friendList = readJson(fKey, FriendList.class);
        if (friendList != null && friendList.getFriends().contains(request.getSenderUsername())) {
            // theyre already friends, so no friend request!
            return "You are already friends!";
        }

        RequestList requestList = readJson(key, RequestList.class);
        if (requestList == null) {
            requestList = new RequestList();
            requestList.setUsername(request.getReceiverUsername());
            requestList.setPendingRequests(new ArrayList<>());
        }

        // don't duplicate requests
        if (!requestList.getPendingRequests().contains(request.getSenderUsername())) {
            requestList.getPendingRequests().add(request.getSenderUsername());
        }
        writeJson(key, requestList);
        return "Successfully sent request!";
    }

    // get the friend list stored for a given user.
    public FriendList getFriendList(String username) throws Exception {
        String key = "users/" + username + "/friends.json";
        FriendList friendList = readJson(key, FriendList.class);
        if (friendList == null) {
            friendList = new FriendList();
            friendList.setUsername(username);
            friendList.setFriends(new ArrayList<>());
        }
        return friendList;
    }

    // get the pending friend requests stored for a given user.
    public RequestList getFriendRequests(String username) throws Exception {
        String key = "users/" + username + "/friend_requests.json";
        RequestList requestList = readJson(key, RequestList.class);
        if (requestList == null) {
            requestList = new RequestList();
            requestList.setUsername(username);
            requestList.setPendingRequests(new ArrayList<>());
        }
        return requestList;
    }

    // accept a friend request: remove the sender's username from the receiver's pending requests and update both users' friend lists.
    public void acceptFriendRequest(FriendRequest request) throws Exception {

        // remove sender username from receiver's pending requests
        String reqKey = "users/" + request.getReceiverUsername() + "/friend_requests.json";
        RequestList requestList = getFriendRequests(request.getReceiverUsername());
        List<String> updatedRequests = requestList.getPendingRequests().stream()
                .filter(sender -> !sender.equals(request.getSenderUsername()))
                .collect(Collectors.toList());
        requestList.setPendingRequests(updatedRequests);
        writeJson(reqKey, requestList);

       
        // update friend list for the receiver
        String receiverFriendsKey = "users/" + request.getReceiverUsername() + "/friends.json";
        FriendList receiverFriendList = getFriendList(request.getReceiverUsername());
        if (!receiverFriendList.getFriends().contains(request.getSenderUsername())) {
            receiverFriendList.getFriends().add(request.getSenderUsername());
        }

        writeJson(receiverFriendsKey, receiverFriendList);


        // update friend list for the sender
        String senderFriendsKey = "users/" + request.getSenderUsername() + "/friends.json";
        FriendList senderFriendList = getFriendList(request.getSenderUsername());
        if (!senderFriendList.getFriends().contains(request.getReceiverUsername())) {
            senderFriendList.getFriends().add(request.getReceiverUsername());
        }

        writeJson(senderFriendsKey, senderFriendList);
    }

    // remove sender username from receiver's pending requests
    public void declineFriendRequest(FriendRequest request) throws Exception {
        String reqKey = "users/" + request.getReceiverUsername() + "/friend_requests.json";

        RequestList requestList = getFriendRequests(request.getReceiverUsername());

        List<String> updatedRequests = requestList.getPendingRequests().stream()
                .filter(sender -> !sender.equals(request.getSenderUsername()))
                .collect(Collectors.toList());

        requestList.setPendingRequests(updatedRequests);
        writeJson(reqKey, requestList);
    }
}
