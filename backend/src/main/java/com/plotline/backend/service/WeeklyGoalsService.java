package com.plotline.backend.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

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
    private static final Logger log = LoggerFactory.getLogger(WeeklyGoalsService.class);


  private final S3Client s3Client;
  private final String bucketName = "plotline-database-bucket";
  private final UserProfileService userProfileService;
  private final ChatMessageService chatMessageService;

  public WeeklyGoalsService(UserProfileService userProfileService, ChatMessageService chatMessageService, S3Client s3Client) {
    this.chatMessageService = chatMessageService;
    this.userProfileService = userProfileService;
    this.s3Client = s3Client; // shared client from AWSConfig
  }

  public Map<String, Object> getWeeklyGoals(String username) {
    try {
      String key = "users/" + normalize(username) + "/weekly-goals.json";

      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      byte[] data = objectBytes.asByteArray();

      ObjectMapper objectMapper = new ObjectMapper();
      return objectMapper.readValue(data, Map.class);
    } catch (NoSuchKeyException e) {
      log.debug("⚠️ No weekly goals file found for {}, returning empty list.", username);
      Map<String, Object> emptyData = new HashMap<>();
      emptyData.put("weeklyGoals", new ArrayList<>());
      return emptyData;
    } catch (IOException e) {
      throw new RuntimeException("Error parsing JSON from S3", e);
    } catch (Exception e) {
      throw new RuntimeException("Error retrieving file from S3", e);
    }
  }

  static String completedMessage(TaskItem task) {
    return "Has completed \"" + task.getName() + "\" from their weekly goals!";
  }

  /** one weekly goal, or null */
  public TaskItem findGoal(String username, int taskId) {
    try {
      byte[] data = s3Client.getObjectAsBytes(GetObjectRequest.builder()
          .bucket(bucketName).key("users/" + normalize(username) + "/weekly-goals.json").build()).asByteArray();
      ObjectMapper objectMapper = new ObjectMapper();
      objectMapper.registerModule(new JavaTimeModule());
      Map<String, List<TaskItem>> goalsData = objectMapper.readValue(data, new TypeReference<>() {
      });
      for (TaskItem task : goalsData.getOrDefault("weeklyGoals", List.of())) {
        if (task.getId() == taskId) return task;
      }
      return null;
    } catch (NoSuchKeyException e) {
      return null;
    } catch (Exception e) {
      log.error("findGoal failed", e);
      return null;
    }
  }

  public boolean addGoalToS3(String username, TaskItem newTask) {
    try {
      String key = "users/" + normalize(username) + "/weekly-goals.json";
      log.debug("📡 Fetching existing goals from: {}", key);

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
      log.debug("⚠️ File not found, creating a new one.");

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
        log.error("addGoalToS3 failed", ex);
        return false;
      }
    } catch (Exception e) {
      log.error("addGoalToS3 failed", e);
      return false;
    }
  }

  public boolean deleteGoalFromS3(String username, int taskId) {
    try {
      String key = "users/" + normalize(username) + "/weekly-goals.json";
      log.debug("📡 Fetching existing goals from: {}", key);

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
      log.debug("⚠️ File not found, nothing to delete.");
      return false;
    } catch (Exception e) {
      log.error("deleteGoalFromS3 failed", e);
      return false;
    }
  }

  public boolean updateGoalInS3(String username, int taskId, TaskItem updatedTask) {
    try {
      String key = "users/" + normalize(username) + "/weekly-goals.json";
      log.debug("📡 Fetching existing goals from: {}", key);

      // Fetch existing goals
      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      String jsonData = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      ObjectMapper objectMapper = new ObjectMapper();
      objectMapper.registerModule(new JavaTimeModule()); // goals have LocalDate due dates
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
      log.debug("⚠️ File not found, cannot update.");
      return false;
    } catch (Exception e) {
      log.error("updateGoalInS3 failed", e);
      return false;
    }
  }

  public boolean resetGoalsInS3(String username) {
    try {
      String key = "users/" + normalize(username) + "/weekly-goals.json";
      log.debug("📡 Resetting all goals for: {}", key);

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
      log.debug("⚠️ File not found, nothing to reset.");
      return false;
    } catch (Exception e) {
      log.error("resetGoalsInS3 failed", e);
      return false;
    }
  }

  public boolean updateGoalCompletionInS3(String username, int taskId, boolean isCompleted) {
    try {
      String key = "users/" + normalize(username) + "/weekly-goals.json";
      log.debug("📡 Fetching existing goals from: {}", key);

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
          .peek(task -> { if (task.getId() == taskId) task.setCompleted(isCompleted); }) // keeps its reminders
          .toList();

      goalsData.put("weeklyGoals", updatedGoals);
      String updatedJson = objectMapper.writeValueAsString(goalsData);

      for (TaskItem task : goalsData.get("weeklyGoals")) {
          if (task.getId() == taskId) {
              // tell friends in Chat when it's checked off; take it back if it's unchecked
              String message = completedMessage(task);
              if (isCompleted) chatMessageService.postOnce(username, message);
              else chatMessageService.retract(username, message);
          }
      }

      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedJson));
      return true;

    } catch (NoSuchKeyException e) {
      log.debug("⚠️ File not found, cannot update.");
      return false;
    } catch (Exception e) {
      log.error("updateGoalCompletionInS3 failed", e);
      return false;
    }
  }

  /** This week's costs by category; empty if none are saved yet. */
  public Map<String, Double> getWeeklyCosts(String username) {
    Map<String, Double> costs = readNumbers("users/" + normalize(username) + "/weekly_costs.json", "costs");
    return costs != null ? costs : new HashMap<>();
  }

  /** The weekly budget (edited if the user changed it, else the one from the quiz); empty if there's none yet. */
  public Map<String, Double> getWeeklyBudget(String username) {
    String user = normalize(username);
    Map<String, Double> budget = readNumbers("users/" + user + "/weekly-budget-edited.json", "budget");
    if (budget == null) budget = readNumbers("users/" + user + "/weekly-budget.json", null);
    return budget != null ? budget : new HashMap<>();
  }

  // a map of numbers from an S3 JSON file (under `field`, or the whole file); null if the file doesn't exist
  private Map<String, Double> readNumbers(String key, String field) {
    try {
      GetObjectRequest request = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();
      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(request);
      Map<String, Object> raw = new ObjectMapper().readValue(objectBytes.asByteArray(), new TypeReference<>() {
      });
      Object numbers = field == null ? raw : raw.get(field);
      Map<String, Double> result = new HashMap<>();
      if (numbers instanceof Map<?, ?> map) {
        map.forEach((k, v) -> {
          if (v instanceof Number n) result.put(String.valueOf(k), n.doubleValue());
        });
      }
      return result;
    } catch (NoSuchKeyException e) {
      return null;
    } catch (Exception e) {
      log.error("Reading {} failed", key, e);
      throw new RuntimeException("Failed to read " + key, e);
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
