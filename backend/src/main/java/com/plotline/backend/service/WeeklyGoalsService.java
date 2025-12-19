package com.plotline.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.plotline.backend.dto.ChatMessage;
import com.plotline.backend.dto.TaskItem;

import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import com.fasterxml.jackson.core.type.TypeReference;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.*;

import io.github.cdimascio.dotenv.Dotenv;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;

import static com.plotline.backend.util.UsernameUtils.normalize;

@Service
public class WeeklyGoalsService {

  private final S3Client s3Client;
  private final String bucketName = "plotline-database-bucket";
  private final UserProfileService userProfileService;
  private final ChatMessageService chatMessageService;

  public WeeklyGoalsService(UserProfileService userProfileService, ChatMessageService chatMessageService) {
    this.chatMessageService = chatMessageService;
    Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();
    String accessKey = dotenv.get("AWS_ACCESS_KEY_ID");
    String secretKey = dotenv.get("AWS_SECRET_ACCESS_KEY");
    String region = dotenv.get("AWS_REGION");

    this.userProfileService = userProfileService;
    this.s3Client = S3Client.builder()
        .region(Region.of(region))
        .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(accessKey, secretKey)))
        .build();
  }

  public Map<String, Object> getWeeklyGoals(String username) {
    try {
      String key = "users/" + normalize(username) + "/weekly-goals.json"; // Path to JSON file in S3
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
      String key = "users/" + normalize(username) + "/weekly-goals.json";
      System.out.println("📡 Fetching existing goals from: " + key);

      // Fetch existing goals
      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      // Register JavaTimeModule to support LocalDate serialization
      ObjectMapper objectMapper = new ObjectMapper();
      objectMapper.registerModule(new JavaTimeModule());

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

      // weekly goal creator trophy - increment by 1
      userProfileService.incrementTrophy(username, "weekly-goals-creator", 1);

      return true; // Success

    } catch (NoSuchKeyException e) {
      System.out.println("⚠️ File not found, creating a new one.");

      // Create a new goal list if the file does not exist
      Map<String, List<TaskItem>> newGoalData = new HashMap<>();
      newGoalData.put("weeklyGoals", new ArrayList<>(Collections.singletonList(newTask)));

      try {
        ObjectMapper objectMapper = new ObjectMapper();
        objectMapper.registerModule(new JavaTimeModule());

        String newJson = objectMapper.writeValueAsString(newGoalData);

        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
            .bucket(bucketName)
            .key("users/" + normalize(username) + "/weekly-goals.json")
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
      String key = "users/" + normalize(username) + "/weekly-goals.json";
      System.out.println("📡 Fetching existing goals from: " + key);

      // Fetch existing goals
      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      ObjectMapper objectMapper = new ObjectMapper();
      objectMapper.registerModule(new JavaTimeModule());
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
      String key = "users/" + normalize(username) + "/weekly-goals.json";
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
      String key = "users/" + normalize(username) + "/weekly-goals.json";
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
      String key = "users/" + normalize(username) + "/weekly-goals.json";
      System.out.println("📡 Fetching existing goals from: " + key);

      // Fetch existing goals
      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      ObjectMapper objectMapper = new ObjectMapper();
      objectMapper.registerModule(new JavaTimeModule());

      Map<String, List<TaskItem>> goalsData = objectMapper.readValue(jsonData, new TypeReference<>() {
      });
      List<TaskItem> updatedGoals = goalsData.get("weeklyGoals").stream()
          .map(task -> task.getId() == taskId
              ? new TaskItem(task.getId(), task.getName(), isCompleted, task.getPriority(), task.getDueDate())
              : task)
          .toList();

      goalsData.put("weeklyGoals", updatedGoals);
      String updatedJson = objectMapper.writeValueAsString(goalsData);

      for (TaskItem task : goalsData.get("weeklyGoals")) {
          if (task.getId() == taskId) {
              // post to chat when goal is completed
              if (isCompleted) {
                  ChatMessage msg = new ChatMessage();
                  msg.setCreator(username);
                  msg.setContent("Has completed \"" + task.getName() + "\" from their weekly goals!");
                  chatMessageService.postMessage(username, msg);
              }
          }
      }

      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedJson));
      return true;

    } catch (NoSuchKeyException e) {
      System.out.println("⚠️ File not found, cannot update.");
      return false;
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
  }

  public Map<String, Double> getWeeklyCosts(String username) {
    try {
      String key = "users/" + normalize(username) + "/weekly_costs.json";
      GetObjectRequest request = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(request);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      ObjectMapper objectMapper = new ObjectMapper();
      Map<String, Object> rawData = objectMapper.readValue(jsonData, new TypeReference<>() {
      });
      Map<String, Double> costs = (Map<String, Double>) rawData.get("costs");

      return costs;
    } catch (Exception e) {
      e.printStackTrace();
      throw new RuntimeException("Failed to fetch weekly costs", e);
    }
  }

  public Map<String, Double> getWeeklyBudget(String username) {
    try {
      String key = "users/" + normalize(username) + "/weekly-budget-edited.json";
      GetObjectRequest request = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(request);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      ObjectMapper objectMapper = new ObjectMapper();
      Map<String, Object> rawData = objectMapper.readValue(jsonData, new TypeReference<>() {
      });
      Map<String, Double> budget = (Map<String, Double>) rawData.get("budget");

      return budget;
    } catch (Exception e) {
      e.printStackTrace();
      throw new RuntimeException("Failed to fetch weekly budget", e);
    }
  }

  public Map<String, Double> getFinancialSummary(String username) {
    Map<String, Double> costs = getWeeklyCosts(username);
    Map<String, Double> budget = getWeeklyBudget(username);

    double totalCosts = costs.values().stream().mapToDouble(Double::doubleValue).sum();
    double totalBudget = budget.values().stream().mapToDouble(Double::doubleValue).sum();

    Map<String, Double> summary = new HashMap<>();
    summary.put("totalCosts", totalCosts);
    summary.put("totalBudget", totalBudget);

    return summary;
  }

}
