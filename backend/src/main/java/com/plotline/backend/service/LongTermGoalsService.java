package com.plotline.backend.service;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.stereotype.Service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.plotline.backend.dto.ChatMessage;
import com.plotline.backend.dto.LongTermGoal;
import com.plotline.backend.dto.LongTermStep;

import io.github.cdimascio.dotenv.Dotenv;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

@Service
public class LongTermGoalsService {
  private final S3Client s3Client;
  private final String bucketName = "plotline-database-bucket";
  private final UserProfileService userProfileService;
  private final ChatMessageService chatMessageService;

  public LongTermGoalsService(UserProfileService userProfileService, 
                              ChatMessageService chatMessageService) {
    this.chatMessageService = chatMessageService;
    Dotenv dotenv = Dotenv.load();
    String accessKey = dotenv.get("AWS_ACCESS_KEY_ID");
    String secretKey = dotenv.get("AWS_SECRET_ACCESS_KEY");
    String region = dotenv.get("AWS_REGION");

    this.userProfileService = userProfileService;
    this.s3Client = S3Client.builder()
        .region(Region.of(region))
        .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(accessKey, secretKey)))
        .build();
  }

  public boolean addLongTermGoalToS3(String username, LongTermGoal newGoal) {
    try {
      String key = "users/" + username + "/long-term-goals.json";

      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      ObjectMapper objectMapper = new ObjectMapper();
      Map<String, List<LongTermGoal>> goalsData = objectMapper.readValue(jsonData, new TypeReference<>() {
      });
      goalsData.get("longTermGoals").add(newGoal);

      String updatedJson = objectMapper.writeValueAsString(goalsData);

      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedJson));
      return true;

    } catch (NoSuchKeyException e) {
      // First goal, create new file
      Map<String, List<LongTermGoal>> newData = new HashMap<>();
      newData.put("longTermGoals", new ArrayList<>(List.of(newGoal)));

      try {
        String newJson = new ObjectMapper().writeValueAsString(newData);

        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
            .bucket(bucketName)
            .key("users/" + username + "/long-term-goals.json")
            .build();

        s3Client.putObject(putObjectRequest, RequestBody.fromString(newJson));
        return true;
      } catch (IOException ex) {
        ex.printStackTrace();
        return false;
      }
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
  }

  public Map<String, Object> getLongTermGoals(String username) {
    try {
      String key = "users/" + username + "/long-term-goals.json";

      System.out.println("📡 Fetching long-term goals from: " + key);

      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      byte[] data = objectBytes.asByteArray();

      ObjectMapper objectMapper = new ObjectMapper();
      return objectMapper.readValue(data, Map.class);

    } catch (NoSuchKeyException e) {
      System.out.println("⚠️ No long-term goals file found, returning empty list.");

      Map<String, Object> emptyData = new HashMap<>();
      emptyData.put("longTermGoals", new ArrayList<>());
      return emptyData;

    } catch (IOException e) {
      throw new RuntimeException("Error parsing long-term goals JSON from S3", e);

    } catch (Exception e) {
      throw new RuntimeException("Error retrieving long-term goals file from S3", e);
    }
  }

  public boolean updateStepCompletionInS3(String username, UUID goalId, UUID stepId, boolean isCompleted) {
    try {
      String key = "users/" + username + "/long-term-goals.json";
      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      ObjectMapper objectMapper = new ObjectMapper();
      objectMapper.registerModule(new JavaTimeModule());

      Map<String, List<LongTermGoal>> goalsData = objectMapper.readValue(
          jsonData, new TypeReference<>() {
          });

      List<LongTermGoal> longTermGoals = goalsData.get("longTermGoals");

      for (LongTermGoal goal : longTermGoals) {
        if (goal.getId().equals(goalId)) {


          for (LongTermStep step : goal.getSteps()) {
            if (step.getId().equals(stepId)) {
              step.setCompleted(isCompleted);
              break;
            }
          }

          // post to chat if all steps are completed
          boolean allCompleted = goal.getSteps().stream()
          .allMatch(LongTermStep::isCompleted);
          if (allCompleted) {
              String goalName = goal.getTitle();

              ChatMessage msg = new ChatMessage();
              msg.setCreator(username);
              msg.setContent("Has completed the long-term goal \"" + goalName + "\"!");
              chatMessageService.postMessage(username, msg);
          }
          break;
        }
      }

      // Save updated JSON
      String updatedJson = objectMapper.writeValueAsString(goalsData);

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

  public boolean resetLongTermGoalsInS3(String username) {
    try {
      String key = "users/" + username + "/long-term-goals.json";
      System.out.println("📡 Resetting long-term goals for: " + key);

      Map<String, List<LongTermGoal>> emptyGoalData = Map.of("longTermGoals", new ArrayList<>());

      ObjectMapper objectMapper = new ObjectMapper();
      String emptyJson = objectMapper.writeValueAsString(emptyGoalData);

      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      s3Client.putObject(putObjectRequest, RequestBody.fromString(emptyJson));
      return true;

    } catch (NoSuchKeyException e) {
      System.out.println("⚠️ Long-term goals file not found, nothing to reset.");
      return false;
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
  }

  /* Archive a long term goal */
  public boolean archiveLongTermGoalInS3(String username, UUID goalId) {
    try {
      String key = "users/" + username + "/long-term-goals.json";
      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      ObjectMapper objectMapper = new ObjectMapper();
      objectMapper.registerModule(new JavaTimeModule());

      Map<String, List<LongTermGoal>> goalsData = objectMapper.readValue(jsonData, new TypeReference<>() {
      });

      List<LongTermGoal> longTermGoals = goalsData.getOrDefault("longTermGoals", new ArrayList<>());
      List<LongTermGoal> archivedGoals = goalsData.getOrDefault("archivedGoals", new ArrayList<>());

      LongTermGoal goalToArchive = null;
      for (LongTermGoal goal : longTermGoals) {
        if (goal.getId().equals(goalId)) {
          goalToArchive = goal;
          break;
        }
      }

      if (goalToArchive != null) {
        longTermGoals.remove(goalToArchive);
        archivedGoals.add(goalToArchive);
        goalsData.put("longTermGoals", longTermGoals);
        goalsData.put("archivedGoals", archivedGoals);

        String updatedJson = objectMapper.writeValueAsString(goalsData);
        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
            .bucket(bucketName)
            .key(key)
            .build();
        s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedJson));
        return true;
      } else {
        return false;
      }
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
  }

  /* Unarchive a long term goal */
  public boolean unarchiveLongTermGoalInS3(String username, UUID goalId) {
    try {
      String key = "users/" + username + "/long-term-goals.json";
      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      ObjectMapper objectMapper = new ObjectMapper();
      objectMapper.registerModule(new JavaTimeModule());

      Map<String, List<LongTermGoal>> goalsData = objectMapper.readValue(jsonData, new TypeReference<>() {
      });

      List<LongTermGoal> longTermGoals = goalsData.getOrDefault("longTermGoals", new ArrayList<>());
      List<LongTermGoal> archivedGoals = goalsData.getOrDefault("archivedGoals", new ArrayList<>());

      LongTermGoal goalToUnarchive = null;
      for (LongTermGoal goal : archivedGoals) {
        if (goal.getId().equals(goalId)) {
          goalToUnarchive = goal;
          break;
        }
      }

      if (goalToUnarchive != null) {
        archivedGoals.remove(goalToUnarchive);
        longTermGoals.add(goalToUnarchive);
        goalsData.put("longTermGoals", longTermGoals);
        goalsData.put("archivedGoals", archivedGoals);

        String updatedJson = objectMapper.writeValueAsString(goalsData);
        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
            .bucket(bucketName)
            .key(key)
            .build();
        s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedJson));
        return true;
      } else {
        return false;
      }
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
  }

}
