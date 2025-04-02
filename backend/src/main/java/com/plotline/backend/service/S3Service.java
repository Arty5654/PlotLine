package com.plotline.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.plotline.backend.dto.LongTermGoal;
import com.plotline.backend.dto.LongTermStep;
import com.plotline.backend.dto.TaskItem;

import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.services.s3.model.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.*;

import org.springframework.stereotype.Service;

import io.github.cdimascio.dotenv.Dotenv;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;

import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;

@Service
public class S3Service {
  private final S3Client s3Client;
  private final String bucketName = "plotline-database-bucket";

  public S3Service() {
    Dotenv dotenv = Dotenv.load(); // Load .env file
    String accessKey = dotenv.get("AWS_ACCESS_KEY_ID");
    String secretKey = dotenv.get("AWS_SECRET_ACCESS_KEY");
    String region = dotenv.get("AWS_REGION");
    String jwtKey = dotenv.get("JWT_SECRET_KEY");

    this.s3Client = S3Client.builder()
        .region(Region.of(region))
        .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(accessKey, secretKey)))
        .build();
  }

  public void uploadFile(String fileName, InputStream inputStream, long contentLength) {
    try {
      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(fileName)
          .contentLength(contentLength)
          .build();

      s3Client.putObject(putObjectRequest, RequestBody.fromInputStream(inputStream, contentLength));
    } catch (Exception e) {
      throw new RuntimeException("Error uploading file to S3", e);
    }
  }

  public byte[] downloadFile(String fileName) {
    try {
      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(fileName)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      return objectBytes.asByteArray();
    } catch (Exception e) {
      throw new RuntimeException("Error downloading file from S3", e);
    }
  }

  public void deleteFile(String fileName) {
    try {
      DeleteObjectRequest deleteObjectRequest = DeleteObjectRequest.builder()
          .bucket(bucketName)
          .key(fileName)
          .build();

      s3Client.deleteObject(deleteObjectRequest);
    } catch (Exception e) {
      throw new RuntimeException("Error deleting file from S3", e);
    }
  }

  public Map<String, Object> getWeeklyGoals(String username) {
    try {
      String key = "users/" + username + "/weekly-goals.json"; // Path to JSON file in S3
      System.out.println("\n\n\n\n\n\n\nFetching from S3: " + key + "\n\n\n\n\n\n\n"); // Debugging log

      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      byte[] data = objectBytes.asByteArray();

      // Convert JSON to Java Map
      ObjectMapper objectMapper = new ObjectMapper();
      return objectMapper.readValue(data, Map.class);
    } catch (IOException e) {
      throw new RuntimeException("Error parsing JSON from S3", e);
    } catch (Exception e) {
      throw new RuntimeException("Error retrieving file from S3", e);
    }
  }

  public boolean addGoalToS3(String username, TaskItem newTask) {
    try {
      String key = "users/" + username + "/weekly-goals.json";
      System.out.println("📡 Fetching existing goals from: " + key);

      // Fetch existing goals
      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      ObjectMapper objectMapper = new ObjectMapper();
      Map<String, List<TaskItem>> goalsData = objectMapper.readValue(jsonData, new TypeReference<>() {
      });

      // Add the new goal to the existing list
      goalsData.get("weeklyGoals").add(newTask);

      // Convert updated list back to JSON
      String updatedJson = objectMapper.writeValueAsString(goalsData);

      // Upload updated JSON back to S3
      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedJson));

      return true; // Success

    } catch (NoSuchKeyException e) {
      System.out.println("⚠️ File not found, creating a new one.");

      // Create a new goal list if the file does not exist
      Map<String, List<TaskItem>> newGoalData = new HashMap<>();
      newGoalData.put("weeklyGoals", new ArrayList<>(Collections.singletonList(newTask)));

      try {
        String newJson = new ObjectMapper().writeValueAsString(newGoalData);

        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
            .bucket(bucketName)
            .key("users/" + username + "/weekly-goals.json")
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

  public boolean deleteGoalFromS3(String username, int taskId) {
    try {
      String key = "users/" + username + "/weekly-goals.json";
      System.out.println("📡 Fetching existing goals from: " + key);

      // Fetch existing goals
      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      ObjectMapper objectMapper = new ObjectMapper();
      Map<String, List<TaskItem>> goalsData = objectMapper.readValue(jsonData, new TypeReference<>() {
      });

      // Remove task by ID
      List<TaskItem> updatedGoals = goalsData.get("weeklyGoals").stream()
          .filter(task -> task.getId() != taskId)
          .toList();

      // Update JSON data
      goalsData.put("weeklyGoals", updatedGoals);
      String updatedJson = objectMapper.writeValueAsString(goalsData);

      // Upload updated JSON back to S3
      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedJson));

      return true; // Success

    } catch (NoSuchKeyException e) {
      System.out.println("⚠️ File not found, nothing to delete.");
      return false;
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
  }

  public boolean updateGoalInS3(String username, int taskId, TaskItem updatedTask) {
    try {
      String key = "users/" + username + "/weekly-goals.json";
      System.out.println("📡 Fetching existing goals from: " + key);

      // Fetch existing goals
      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      ObjectMapper objectMapper = new ObjectMapper();
      Map<String, List<TaskItem>> goalsData = objectMapper.readValue(jsonData, new TypeReference<>() {
      });

      // Update the task in the list
      List<TaskItem> updatedGoals = goalsData.get("weeklyGoals").stream()
          .map(task -> task.getId() == taskId ? updatedTask : task)
          .toList();

      // Save updated goals back to S3
      goalsData.put("weeklyGoals", updatedGoals);
      String updatedJson = objectMapper.writeValueAsString(goalsData);

      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedJson));

      return true; // Success

    } catch (NoSuchKeyException e) {
      System.out.println("⚠️ File not found, cannot update.");
      return false;
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
  }

  public boolean resetGoalsInS3(String username) {
    try {
      String key = "users/" + username + "/weekly-goals.json";
      System.out.println("📡 Resetting all goals for: " + key);

      // Create an empty goal list
      Map<String, List<TaskItem>> emptyGoalData = Map.of("weeklyGoals", new ArrayList<>());

      // Convert to JSON
      ObjectMapper objectMapper = new ObjectMapper();
      String emptyJson = objectMapper.writeValueAsString(emptyGoalData);

      // Upload empty JSON back to S3
      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      s3Client.putObject(putObjectRequest, RequestBody.fromString(emptyJson));

      return true; // Success

    } catch (NoSuchKeyException e) {
      System.out.println("⚠️ File not found, nothing to reset.");
      return false;
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
  }

  public boolean updateGoalCompletionInS3(String username, int taskId, boolean isCompleted) {
    try {
      String key = "users/" + username + "/weekly-goals.json";
      System.out.println("📡 Fetching existing goals from: " + key);

      // Fetch existing goals
      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      ObjectMapper objectMapper = new ObjectMapper();
      Map<String, List<TaskItem>> goalsData = objectMapper.readValue(jsonData, new TypeReference<>() {
      });

      // Update the completion status
      List<TaskItem> updatedGoals = goalsData.get("weeklyGoals").stream()
          .map(task -> task.getId() == taskId
              ? new TaskItem(task.getId(), task.getName(), isCompleted, task.getPriority())
              : task)

          .toList();

      // Save updated goals back to S3
      goalsData.put("weeklyGoals", updatedGoals);
      String updatedJson = objectMapper.writeValueAsString(goalsData);

      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedJson));

      return true; // Success

    } catch (NoSuchKeyException e) {
      System.out.println("⚠️ File not found, cannot update.");
      return false;
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
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

}
