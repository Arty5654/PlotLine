package com.plotline.backend.service;

import com.plotline.backend.dto.FriendList;
import com.plotline.backend.dto.FriendRequest;
import com.plotline.backend.dto.RequestList;
import com.fasterxml.jackson.databind.ObjectMapper;
import static com.plotline.backend.util.UsernameUtils.normalize;

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
        String sender = normalize(request.getSenderUsername());
        String receiver = normalize(request.getReceiverUsername());

        // update existing (accepted or declined) friend requests
        String status = request.getStatus();
        if ("ACCEPTED".equalsIgnoreCase(status)) {
            acceptFriendRequest(new FriendRequest(sender, receiver, status));
            return "Accepted";
        } else if ("DECLINED".equalsIgnoreCase(status)) {
            declineFriendRequest(new FriendRequest(sender, receiver, status));
            return "Declined";
        }

        String fKey = "users/" + receiver + "/friends.json"; // friends key
        String key = "users/" + receiver + "/friend_requests.json"; // requests key

        FriendList friendList = readJson(fKey, FriendList.class);
        if (friendList != null && friendList.getFriends().contains(sender)) {
            // theyre already friends, so no friend request!
            return "You are already friends!";
        }

        RequestList requestList = readJson(key, RequestList.class);
        if (requestList == null) {
            requestList = new RequestList();
            requestList.setUsername(receiver);
            requestList.setPendingRequests(new ArrayList<>());
        }

        // don't duplicate requests
        if (!requestList.getPendingRequests().contains(sender)) {
            requestList.getPendingRequests().add(sender);
        }
        writeJson(key, requestList);
        return "Successfully sent request!";
    }

    // get the friend list stored for a given user.
    public FriendList getFriendList(String username) throws Exception {
        String normUser = normalize(username);
        String key = "users/" + normUser + "/friends.json";
        FriendList friendList = readJson(key, FriendList.class);
        if (friendList == null) {
            friendList = new FriendList();
            friendList.setUsername(normUser);
            friendList.setFriends(new ArrayList<>());
        }
        return friendList;
    }

    // get the pending friend requests stored for a given user.
    public RequestList getFriendRequests(String username) throws Exception {
        String normUser = normalize(username);
        String key = "users/" + normUser + "/friend_requests.json";
        RequestList requestList = readJson(key, RequestList.class);
        if (requestList == null) {
            requestList = new RequestList();
            requestList.setUsername(normUser);
            requestList.setPendingRequests(new ArrayList<>());
        }
        return requestList;
    }

    // accept a friend request: remove the sender's username from the receiver's pending requests and update both users' friend lists.
    public void acceptFriendRequest(FriendRequest request) throws Exception {
        String sender = normalize(request.getSenderUsername());
        String receiver = normalize(request.getReceiverUsername());

        // remove sender username from receiver's pending requests
        String reqKey = "users/" + receiver + "/friend_requests.json";
        RequestList requestList = getFriendRequests(receiver);
        List<String> updatedRequests = requestList.getPendingRequests().stream()
                .filter(s -> !s.equals(sender))
                .collect(Collectors.toList());
        requestList.setPendingRequests(updatedRequests);
        writeJson(reqKey, requestList);

       
        // update friend list for the receiver
        String receiverFriendsKey = "users/" + receiver + "/friends.json";
        FriendList receiverFriendList = getFriendList(receiver);
        if (!receiverFriendList.getFriends().contains(sender)) {
            receiverFriendList.getFriends().add(sender);
        }

        writeJson(receiverFriendsKey, receiverFriendList);


        // update friend list for the sender
        String senderFriendsKey = "users/" + sender + "/friends.json";
        FriendList senderFriendList = getFriendList(sender);
        if (!senderFriendList.getFriends().contains(receiver)) {
            senderFriendList.getFriends().add(receiver);
        }

        writeJson(senderFriendsKey, senderFriendList);
    }

    // remove sender username from receiver's pending requests
    public void declineFriendRequest(FriendRequest request) throws Exception {
        String sender = normalize(request.getSenderUsername());
        String receiver = normalize(request.getReceiverUsername());
        String reqKey = "users/" + receiver + "/friend_requests.json";

        RequestList requestList = getFriendRequests(receiver);

        List<String> updatedRequests = requestList.getPendingRequests().stream()
                .filter(s -> !s.equals(sender))
                .collect(Collectors.toList());

        requestList.setPendingRequests(updatedRequests);
        writeJson(reqKey, requestList);
    }

    // remove a friendship (from both users' friend lists)
    public void removeFriend(String userA, String userB) throws Exception {
        String u1 = normalize(userA);
        String u2 = normalize(userB);

        FriendList listA = getFriendList(u1);
        listA.getFriends().removeIf(f -> f.equalsIgnoreCase(u2));
        writeJson("users/" + u1 + "/friends.json", listA);

        FriendList listB = getFriendList(u2);
        listB.getFriends().removeIf(f -> f.equalsIgnoreCase(u1));
        writeJson("users/" + u2 + "/friends.json", listB);

        // also clean any pending requests between them
        RequestList reqA = getFriendRequests(u1);
        reqA.getPendingRequests().removeIf(f -> f.equalsIgnoreCase(u2));
        writeJson("users/" + u1 + "/friend_requests.json", reqA);

        RequestList reqB = getFriendRequests(u2);
        reqB.getPendingRequests().removeIf(f -> f.equalsIgnoreCase(u1));
        writeJson("users/" + u2 + "/friend_requests.json", reqB);
    }
}
