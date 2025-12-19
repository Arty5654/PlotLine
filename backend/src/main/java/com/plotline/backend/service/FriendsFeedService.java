package com.plotline.backend.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.plotline.backend.dto.FriendList;
import com.plotline.backend.dto.FriendPost;

import org.springframework.stereotype.Service;
import io.github.cdimascio.dotenv.Dotenv;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;

@Service
public class FriendsFeedService {
  private final S3Client s3Client;
  private final String bucketName = "plotline-database-bucket";

  public FriendsFeedService() {
    Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();
    String accessKey = dotenv.get("AWS_ACCESS_KEY_ID");
    String secretKey = dotenv.get("AWS_SECRET_ACCESS_KEY");
    String region = dotenv.get("AWS_REGION");

    this.s3Client = S3Client.builder()
        .region(Region.of(region))
        .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(accessKey, secretKey)))
        .build();
  }

  public boolean addPostToFeed(FriendPost post) {
    try {
      String key = "friends-feed/posts.json";

      List<FriendPost> posts;

      try {
        GetObjectRequest getObjectRequest = GetObjectRequest.builder()
            .bucket(bucketName)
            .key(key)
            .build();

        ResponseBytes<?> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
        String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

        ObjectMapper objectMapper = new ObjectMapper();

        posts = objectMapper.readValue(jsonData, new TypeReference<>() {
        });
      } catch (NoSuchKeyException e) {
        posts = new ArrayList<>();
      }

      posts.add(post);

      ObjectMapper objectMapper = new ObjectMapper();

      String updatedJson = objectMapper.writeValueAsString(posts);

      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedJson));

      return true;
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
  }

  public List<FriendPost> getFriendsFeed(String username) {
    try {
      String postsKey = "friends-feed/posts.json";
      String friendsKey = "users/" + username + "/friends.json";

      ObjectMapper objectMapper = new ObjectMapper();

      // 1. Load all posts
      GetObjectRequest postsRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(postsKey)
          .build();

      ResponseBytes<?> postsBytes = s3Client.getObjectAsBytes(postsRequest);
      List<FriendPost> allPosts = objectMapper.readValue(
          postsBytes.asByteArray(), new TypeReference<List<FriendPost>>() {
          });

      // 2. Load user's friends
      List<String> friendsList;
      try {
        GetObjectRequest friendsRequest = GetObjectRequest.builder()
            .bucket(bucketName)
            .key(friendsKey)
            .build();

        ResponseBytes<?> friendsBytes = s3Client.getObjectAsBytes(friendsRequest);

        FriendList friendData = objectMapper.readValue(friendsBytes.asByteArray(), FriendList.class);
        friendsList = friendData.getFriends();
      } catch (NoSuchKeyException e) {
        // If user has no friends list file yet, assume empty
        friendsList = new ArrayList<>();
      }

      // Temporary hardcoded friends list
      // List<String> friendsList = new ArrayList<>();
      // friendsList.add(username); // Always see your own posts

      // 3. Always include the user themself
      friendsList.add(username);

      // 4. Filter posts
      List<FriendPost> filteredPosts = new ArrayList<>();
      for (FriendPost post : allPosts) {
        if (friendsList.contains(post.getUsername())) {
          filteredPosts.add(post);
        }
      }

      return filteredPosts;

    } catch (Exception e) {
      e.printStackTrace();
      return new ArrayList<>();
    }
  }

  public boolean deletePostById(String username, UUID postId) {
    try {
      String key = "friends-feed/posts.json";

      GetObjectRequest getRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<?> bytes = s3Client.getObjectAsBytes(getRequest);
      ObjectMapper mapper = new ObjectMapper();
      List<FriendPost> allPosts = mapper.readValue(bytes.asByteArray(), new TypeReference<>() {
      });

      // Only allow deleting your own posts
      List<FriendPost> updatedPosts = allPosts.stream()
          .filter(post -> !(post.getId().equals(postId) && post.getUsername().equals(username)))
          .toList();

      // Save updated list
      String updatedJson = mapper.writeValueAsString(updatedPosts);
      PutObjectRequest putRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      s3Client.putObject(putRequest, RequestBody.fromString(updatedJson));
      return true;
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
  }

  public boolean toggleLike(String username, UUID postId) {
    try {
      List<FriendPost> posts = loadPosts(); // write a helper that reads JSON
      for (FriendPost post : posts) {
        if (post.getId().equals(postId)) {
          Set<String> likedBy = post.getLikedBy();
          if (likedBy.contains(username)) {
            likedBy.remove(username);
          } else {
            likedBy.add(username);
          }
          break;
        }
      }
      savePosts(posts); // write a helper that writes JSON
      return true;
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
  }

  public boolean addComment(String username, UUID postId, String comment) {
    try {
      List<FriendPost> posts = loadPosts();
      for (FriendPost post : posts) {
        if (post.getId().equals(postId)) {
          post.getComments().add(username + ": " + comment);
          break;
        }
      }
      savePosts(posts);
      return true;
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
  }

  private List<FriendPost> loadPosts() throws IOException {
    String key = "friends-feed/posts.json";

    GetObjectRequest getRequest = GetObjectRequest.builder()
        .bucket(bucketName)
        .key(key)
        .build();

    ResponseBytes<?> objectBytes = s3Client.getObjectAsBytes(getRequest);
    ObjectMapper mapper = new ObjectMapper();
    mapper.registerModule(new JavaTimeModule());

    return mapper.readValue(objectBytes.asByteArray(), new TypeReference<>() {
    });
  }

  private void savePosts(List<FriendPost> posts) throws IOException {
    String key = "friends-feed/posts.json";

    ObjectMapper mapper = new ObjectMapper();
    mapper.registerModule(new JavaTimeModule());
    mapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    String updatedJson = mapper.writeValueAsString(posts);

    PutObjectRequest putRequest = PutObjectRequest.builder()
        .bucket(bucketName)
        .key(key)
        .build();

    s3Client.putObject(putRequest, RequestBody.fromString(updatedJson));
  }

}
