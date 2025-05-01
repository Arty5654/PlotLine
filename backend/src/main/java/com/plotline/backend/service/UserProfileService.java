package com.plotline.backend.service;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import java.time.ZonedDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;

import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import com.plotline.backend.dto.S3UserRecord;
import com.plotline.backend.dto.Trophy;
import com.plotline.backend.dto.UserProfile;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;


import io.github.cdimascio.dotenv.Dotenv;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.ObjectCannedACL;

@Service
public class UserProfileService {

  static DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssXXX");

  private static final List<Trophy> DEFAULT_TROPHIES = List.of(
  //goals

    new Trophy("long-term-goals", "Goal Crusher", "Complete long-term goals!", 
    0, 0, new int[]{1, 5, 10, 30}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),


    new Trophy("weekly-goals-creator", "Weekly Warrior", "Create weekly goals!", 
    0, 0, new int[]{10, 25, 75, 250}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

  //calendar

    new Trophy("calendar-events-created", "Event Planner", "Create events on your calendar!", 
    0, 0, new int[]{5, 15, 50, 100}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("friends-invited", "Group Leader", "Add friends to calendar events!", 
    0, 0, new int[]{5, 20, 50, 100}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

  //budget and stocks

    // TODO
    new Trophy("weekly-budget-met", "Weekly Budgetor", "Under weekly budget limit!", 
    0, 0, new int[]{4, 10, 26, 52}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    // TODO
    new Trophy("monthly-budget-met", "Monthly Budgetor", "Under monthly budget limit!", 
    0, 0, new int[]{1, 3, 6, 12}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("investing-simple", "Stock Spender", "Invested into the stock market!", 
    0, 0, new int[]{1, 5, 20, 50}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("monthly-spending-tracker", "Spending Tracker", "Input Spending data!", 
    0, 0, new int[]{10, 20, 50, 100}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    // TODO
    new Trophy("receipt-photo", "Paper Photographer", "Upload Pictures of Receipts!", 
    0, 0, new int[]{10, 20, 50, 100}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("subcription-spender", "Subscription Maxxer", "Has a lot of subscriptions!", 
    0, 0, new int[]{5, 7, 10, 12}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("watchlist-adder", "Watchful Eye", "Added stocks to the Watchlist!", 
    0, 0, new int[]{3, 10, 20, 50}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

  //groceries
    new Trophy("grocery-lists", "Grocery Guru", "Created grocery Lists!", 
    0, 0, new int[]{3, 10, 20, 50}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("meal-prepper", "Meal Prepper", "Created Recipes based on the Meal!", 
    0, 0, new int[]{3, 10, 20, 50}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

  //sleep
    new Trophy("sleep-tracker", "Someone's Sleepy", "Logged sleep data!", 
    0, 0, new int[]{3, 10, 30, 100}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("sleep-goal", "Well Rested", "Slept for over 8 hours!", 
    0, 0, new int[]{5, 15, 25, 100}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

  //special trophies

    new Trophy("all-around", "All-Around Achiever", "Achieve at least one trophy from each PlotLine Category!", 
    0, 0, new int[]{0, 0, 0, 1}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("llm-investor", "Portfolio Pro", "Created a stock portfolio with the LLM!", 
    0, 0, new int[]{0, 0, 0, 1}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)), 

    new Trophy("first-profile-picture", "Picture Perfect", "Uploaded a profile picture!", 
    0, 0, new int[]{0, 0, 0, 1}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter))

  );


  private final S3Client s3Client;
  private final ObjectMapper objectMapper;
  private final ChatMessageService chatService;
  private final String bucketName = "plotline-database-bucket";
  private final Dotenv dotenv = Dotenv.load();

  public UserProfileService(S3Client s3Client,
                            ChatMessageService chatService) {
      this.s3Client = s3Client;
      this.objectMapper = new ObjectMapper();
      this.chatService = chatService;
  }

  public void saveProfile(UserProfile profile) {
      try {

          String user = objectMapper.writeValueAsString(profile);

          String username = profile.getUsername();
          String key = "users/" + username + "/profile.json";

          PutObjectRequest putRequest = PutObjectRequest.builder().
            bucket(bucketName).
            key(key).
            contentType("application/json").
            build();

            s3Client.putObject(putRequest, RequestBody.fromString(user));

      } catch (JsonProcessingException e) {
          e.printStackTrace();
      }
  }

  public UserProfile getProfile(String username) {
      
      try {

        System.out.println(username);
        String key = "users/" + username + "/profile.json";

        GetObjectRequest getRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

        ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
        String userJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);


        UserProfile profile = objectMapper.readValue(userJson, UserProfile.class);
        return profile;

      } catch (Exception e) {
          return null;
      }
  }

  public String getPhoneNum(String username) {
      
    try {

      System.out.println(username);
      String key = "users/" + username + "/account.json";

      GetObjectRequest getRequest = GetObjectRequest.builder()
        .bucket(bucketName)
        .key(key)
        .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
      String userJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);


      S3UserRecord profile = objectMapper.readValue(userJson, S3UserRecord.class);
      return profile.getPhone();

    } catch (Exception e) {
        return null;
    }
}

  public String uploadProfilePicture(MultipartFile file, String username) throws Exception {
        String fileName = "users/" + username + "/profile_pictures/" + username + ".jpg";

        System.out.println("Uploading profile picture");

        PutObjectRequest putRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(fileName)
                .contentType(file.getContentType())
                .acl(ObjectCannedACL.PUBLIC_READ)
                .build();

        s3Client.putObject(putRequest, RequestBody.fromBytes(file.getBytes()));

        System.out.println("Profile picture uploaded successfully");
        // first profile picture trophy awarded
        incrementTrophy(username, "first-profile-picture", 1);

        return "https://" + bucketName + ".s3.amazonaws.com/" + fileName;
  }

  // TROPHY FUNCTIONS

  public List<Trophy> getTrophies(String username) throws IOException {
    String key = "users/" + username + "/trophies.json";

    try {
      GetObjectRequest getRequest = GetObjectRequest.builder()
      .bucket(bucketName)
      .key(key)
      .build();
      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
      String content = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      // parse json into trophy
      List<Trophy> trophies = objectMapper.readValue(content, new TypeReference<List<Trophy>>() {});
      System.out.println("Trophies: " + trophies);

      // if new trophies were added since this user created their default trophies, add here
      if (trophies.size() < DEFAULT_TROPHIES.size()) {
        Set<String> userTrophyIds = trophies.stream()
          .map(Trophy::getId)
          .collect(Collectors.toSet());

        List<Trophy> updated = new ArrayList<>(trophies);
        for (Trophy defaultTrophy : DEFAULT_TROPHIES) {
          if (!userTrophyIds.contains(defaultTrophy.getId())) {
            updated.add(new Trophy(
              defaultTrophy.getId(),
              defaultTrophy.getName(),
              defaultTrophy.getDescription(),
              0,
              0,
              defaultTrophy.getThresholds(),
              ZonedDateTime.now(ZoneOffset.UTC).format(formatter)             
            ));
          }
        }

        if (updated.size() > trophies.size()) {
          saveTrophies(username, updated);
        }
        trophies = updated;
      }
      return trophies;

    } catch (software.amazon.awssdk.services.s3.model.NoSuchKeyException e) {
      // If the trophies.json file does not exist, create default trophies     
      if (e.awsErrorDetails().errorCode().equals("NoSuchKey")) {
          System.out.println("No trophies found for user: " + username + ". Creating default trophies.");
          return createDefaultTrophies(username);
      } else {
          throw e;
      }
    }


  }

  public void saveTrophies(String username, List<Trophy> trophies) throws IOException {

    String key = "users/" + username + "/trophies.json";
    PutObjectRequest putRequest = PutObjectRequest.builder()
        .bucket(bucketName)
        .key(key)
        .contentType("application/json")
        .build();
    s3Client.putObject(putRequest, RequestBody.fromString(objectMapper.writeValueAsString(trophies)));

    String json = objectMapper.writeValueAsString(trophies);
  }

  public List<Trophy> incrementTrophy(String username, String trophyId, int amount) throws IOException {
    List<Trophy> trophies = getTrophies(username);
    for (Trophy trophy : trophies) {
        if (trophy.getId().equals(trophyId)) {
            trophy.setProgress(trophy.getProgress() + amount);
            int previousLevel = trophy.getLevel();

            // Upgrade logic
            int newLevel = 0;
            for (int i = 0; i < trophy.getThresholds().length; i++) {
                if (trophy.getProgress() >= trophy.getThresholds()[i]) {
                    newLevel = i + 1;
                }
            }
            trophy.setLevel(newLevel);

            String levelName = "";
            if (trophy.getLevel() == 1) {
                levelName = "Bronze";
            } else if (trophy.getLevel() == 2) {
                levelName = "Silver";
            } else if (trophy.getLevel() == 3) {
                levelName = "Gold";
            } else if (trophy.getLevel() == 4) {
                levelName = "Diamond";
            }


            if (newLevel > previousLevel) {
              trophy.setEarnedDate(ZonedDateTime.now(ZoneOffset.UTC).format(formatter));

              try {
                  String content = String.format("Earned the %s level of '%s' trophy!", levelName, trophy.getName());
                  chatService.postMessage(username, new com.plotline.backend.dto.ChatMessage(null, username, null, content));
              } catch (JsonProcessingException e) {
                  // log and continue
                  e.printStackTrace();
              }
            }

            break;
        }

        // check for special trophy
        if (trophy.getId().equals("all-around") && trophy.getLevel() == 0) {
          if (checkAllAroundAchiever(trophies)) {
            trophy.setLevel(4);
            trophy.setProgress(1);
            trophy.setEarnedDate(ZonedDateTime.now(ZoneOffset.UTC).format(formatter));

            try {
              String content = String.format("Earned the 'All Around Achiever' trophy!", trophy.getName());
              chatService.postMessage(username, new com.plotline.backend.dto.ChatMessage(null, username, null, content));
            } catch (JsonProcessingException e) {
              // log and continue
              e.printStackTrace();
            }
          }
        }
    }
    saveTrophies(username, trophies);
    return trophies;
  }

  public List<Trophy> createDefaultTrophies(String username) throws IOException {
    saveTrophies(username, DEFAULT_TROPHIES);
    return DEFAULT_TROPHIES;
  }


  // for all around achiever (one from each plotline category)
  private String getCategoryFromTrophyId(String trophyId) {
    if (trophyId.startsWith("long-term-goals") || trophyId.startsWith("weekly-goals")) {
        return "goals";
    } else if (trophyId.startsWith("calendar") || trophyId.startsWith("friends")) {
        return "calendar";
    } else if (trophyId.startsWith("weekly-budget") || trophyId.startsWith("monthly-budget") ||
               trophyId.startsWith("investing") || trophyId.startsWith("watchlist") ||
               trophyId.startsWith("subcription")) {
        return "budget";
    } else if (trophyId.startsWith("grocery") || trophyId.startsWith("meal-prepper")) {
        return "groceries";
    } else if (trophyId.startsWith("sleep")) {
        return "sleep";
    }

    return null; // if not part of a known category
  }

  public boolean checkAllAroundAchiever(List<Trophy> trophies) {
    Set<String> earnedCategories = new HashSet<>();

    for (Trophy trophy : trophies) {
        if (trophy.getLevel() > 0) {
            String category = getCategoryFromTrophyId(trophy.getId());
            if (category != null) {
                earnedCategories.add(category);
            }
        }
    }
    Set<String> requiredCategories = Set.of(
        "goals", "calendar", "budget", "groceries", "sleep"
    );
    return earnedCategories.containsAll(requiredCategories);
  }

  public void setTrophyProgress(String username, String trophyId, int newProgress) throws IOException {
    List<Trophy> trophies = getTrophies(username);
    for (Trophy trophy : trophies) {
        if (trophy.getId().equals(trophyId)) {
            trophy.setProgress(newProgress);
            int newLevel = 0;
            for (int i = 0; i < trophy.getThresholds().length; i++) {
                if (newProgress >= trophy.getThresholds()[i]) {
                    newLevel = i + 1;
                }
            }
            trophy.setLevel(newLevel);
            if (newLevel > 0 && trophy.getEarnedDate() == null) {
                trophy.setEarnedDate(ZonedDateTime.now(ZoneOffset.UTC).format(formatter));
            }
            break;
        }
    }
    saveTrophies(username, trophies);
}

  
}
