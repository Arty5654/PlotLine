package com.plotline.backend.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

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

import static com.plotline.backend.util.UsernameUtils.normalize;
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
    private static final Logger log = LoggerFactory.getLogger(LongTermGoalsService.class);

  private final S3Client s3Client;
  private final String bucketName = "plotline-database-bucket";
  private final UserProfileService userProfileService;
  private final ChatMessageService chatMessageService;

  public LongTermGoalsService(UserProfileService userProfileService,
                              ChatMessageService chatMessageService, S3Client s3Client) {
    this.chatMessageService = chatMessageService;
    this.userProfileService = userProfileService;
    this.s3Client = s3Client; // shared client from AWSConfig
  }

  public boolean addLongTermGoalToS3(String username, LongTermGoal newGoal) {
    username = normalize(username);
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
        log.error("addLongTermGoalToS3 failed", ex);
        return false;
      }
    } catch (Exception e) {
      log.error("addLongTermGoalToS3 failed", e);
      return false;
    }
  }

  public Map<String, Object> getLongTermGoals(String username) {
    username = normalize(username);
    try {
      String key = "users/" + username + "/long-term-goals.json";

      log.debug("📡 Fetching long-term goals from: {}", key);

      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      byte[] data = objectBytes.asByteArray();

      ObjectMapper objectMapper = new ObjectMapper();
      return objectMapper.readValue(data, Map.class);

    } catch (NoSuchKeyException e) {
      log.debug("⚠️ No long-term goals file found, returning empty list.");

      Map<String, Object> emptyData = new HashMap<>();
      emptyData.put("longTermGoals", new ArrayList<>());
      return emptyData;

    } catch (IOException e) {
      throw new RuntimeException("Error parsing long-term goals JSON from S3", e);

    } catch (Exception e) {
      throw new RuntimeException("Error retrieving long-term goals file from S3", e);
    }
  }

  // every step checked off (a goal with no steps isn't "done")
  private static boolean isDone(LongTermGoal goal) {
    return goal.getSteps() != null && !goal.getSteps().isEmpty()
        && goal.getSteps().stream().allMatch(LongTermStep::isCompleted);
  }

  public boolean updateStepCompletionInS3(String username, UUID goalId, UUID stepId, boolean isCompleted) {
    username = normalize(username);
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
          boolean wasDone = isDone(goal);

          for (LongTermStep step : goal.getSteps()) {
            if (step.getId().equals(stepId)) {
              step.setCompleted(isCompleted);
              break;
            }
          }

          // tell friends in Chat when the last step is checked off; take it back if one is unchecked
          String message = "Has completed the long-term goal \"" + goal.getTitle() + "\"!";
          boolean done = isDone(goal);
          if (done && !wasDone) {
              chatMessageService.postOnce(username, message);
              userProfileService.incrementTrophy(username, "long-term-goals", 1);
          } else if (!done && wasDone) {
              chatMessageService.retract(username, message);
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
      log.error("updateStepCompletionInS3 failed", e);
      return false;
    }
  }

  public boolean resetLongTermGoalsInS3(String username) {
    username = normalize(username);
    try {
      String key = "users/" + username + "/long-term-goals.json";
      log.debug("📡 Resetting long-term goals for: {}", key);

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
      log.debug("⚠️ Long-term goals file not found, nothing to reset.");
      return false;
    } catch (Exception e) {
      log.error("resetLongTermGoalsInS3 failed", e);
      return false;
    }
  }

  /* Archive a long term goal */
  public boolean archiveLongTermGoalInS3(String username, UUID goalId) {
    username = normalize(username);
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
      log.error("archiveLongTermGoalInS3 failed", e);
      return false;
    }
  }

  /* Unarchive a long term goal */
  public boolean unarchiveLongTermGoalInS3(String username, UUID goalId) {
    username = normalize(username);
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
      log.error("unarchiveLongTermGoalInS3 failed", e);
      return false;
    }
  }


  // ── Editing and weekly-goal links ────────────────────────────────────────────

  @FunctionalInterface
  private interface Change {
    /** changes the goals file in place; returns false if nothing matched (nothing is saved) */
    boolean apply(List<LongTermGoal> active, List<LongTermGoal> archived);
  }

  private boolean modify(String username, Change change) {
    String key = "users/" + normalize(username) + "/long-term-goals.json";
    try {
      ObjectMapper objectMapper = new ObjectMapper();
      byte[] data = s3Client.getObjectAsBytes(GetObjectRequest.builder().bucket(bucketName).key(key).build()).asByteArray();
      Map<String, List<LongTermGoal>> goalsData = objectMapper.readValue(data, new TypeReference<>() {
      });
      List<LongTermGoal> active = goalsData.computeIfAbsent("longTermGoals", k -> new ArrayList<>());
      List<LongTermGoal> archived = goalsData.computeIfAbsent("archivedGoals", k -> new ArrayList<>());
      if (!change.apply(active, archived)) return false;
      s3Client.putObject(PutObjectRequest.builder().bucket(bucketName).key(key).build(),
          RequestBody.fromString(objectMapper.writeValueAsString(goalsData)));
      return true;
    } catch (NoSuchKeyException e) {
      return false;
    } catch (Exception e) {
      log.error("Updating long-term goals failed", e);
      return false;
    }
  }

  /** replaces a goal's title, target date, reminders and steps (active or archived) */
  public boolean updateLongTermGoal(String username, UUID goalId, LongTermGoal updated) {
    return modify(username, (active, archived) -> {
      for (List<LongTermGoal> list : List.of(active, archived)) {
        for (int i = 0; i < list.size(); i++) {
          if (list.get(i).getId().equals(goalId)) {
            updated.setId(goalId);
            if (updated.getSteps() == null) updated.setSteps(new ArrayList<>());
            list.set(i, updated);
            return true;
          }
        }
      }
      return false;
    });
  }

  /** the step, or null if the goal or step no longer exists */
  public LongTermStep findStep(String username, UUID goalId, UUID stepId) {
    LongTermStep[] found = new LongTermStep[1];
    modify(username, (active, archived) -> {
      found[0] = stepIn(active, goalId, stepId);
      if (found[0] == null) found[0] = stepIn(archived, goalId, stepId);
      return false; // read only
    });
    return found[0];
  }

  /** links a step to a weekly goal, or unlinks it (null) */
  public boolean setStepWeeklyGoal(String username, UUID goalId, UUID stepId, Integer weeklyGoalId) {
    return modify(username, (active, archived) -> {
      LongTermStep step = stepIn(active, goalId, stepId);
      if (step == null) step = stepIn(archived, goalId, stepId);
      if (step == null) return false;
      step.setWeeklyGoalId(weeklyGoalId);
      return true;
    });
  }

  private static LongTermStep stepIn(List<LongTermGoal> goals, UUID goalId, UUID stepId) {
    for (LongTermGoal goal : goals) {
      if (goal.getId().equals(goalId) && goal.getSteps() != null) {
        for (LongTermStep step : goal.getSteps()) {
          if (step.getId().equals(stepId)) return step;
        }
      }
    }
    return null;
  }
}