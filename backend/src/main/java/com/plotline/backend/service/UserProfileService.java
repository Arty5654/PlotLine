package com.plotline.backend.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
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

import static com.plotline.backend.util.UsernameUtils.normalize;


import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.model.ObjectCannedACL;

@Service
public class UserProfileService {
    private static final Logger log = LoggerFactory.getLogger(UserProfileService.class);


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

    new Trophy("budget-pacer", "Budget Pacer", "Kept spending at least 5% under budget for the month!", 
    0, 0, new int[]{1, 3, 6, 12}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("investing-simple", "Stock Spender", "Invested into the stock market!", 
    0, 0, new int[]{1, 5, 20, 50}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("investing-streak", "Investor Streak", "Kept investing consistently!", 
    0, 0, new int[]{2, 4, 8, 12}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("monthly-spending-tracker", "Spending Tracker", "Input Spending data!", 
    0, 0, new int[]{10, 20, 50, 100}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    // TODO
    new Trophy("receipt-photo", "Paper Photographer", "Upload Pictures of Receipts!", 
    0, 0, new int[]{10, 20, 50, 100}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("subscription-spender", "Subscription Maxxer", "Has a lot of subscriptions!", 
    0, 0, new int[]{5, 7, 10, 12}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("healthy-eater", "Healthy Eater", "Shifted spend toward groceries and away from eating out!", 
    0, 0, new int[]{1, 3, 6, 12}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("watchlist-adder", "Watchful Eye", "Added stocks to the Watchlist!", 
    0, 0, new int[]{3, 10, 20, 50}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

  //groceries
    new Trophy("grocery-lists", "Grocery Guru", "Created grocery Lists!", 
    0, 0, new int[]{3, 10, 20, 50}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("meal-prepper", "Meal Prepper", "Created Recipes based on the Meal!", 
    0, 0, new int[]{3, 10, 20, 50}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

  //nutrition
    new Trophy("nutrition-logger", "Calorie Counter", "Log food to your nutrition diary!",
    0, 0, new int[]{5, 15, 50, 150}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("nutrition-photo", "Food Photographer", "Analyze food with AI photo recognition!",
    0, 0, new int[]{3, 10, 25, 50}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("nutrition-barcode", "Barcode Pro", "Scan food barcodes!",
    0, 0, new int[]{5, 15, 40, 100}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("nutrition-meal-creator", "Meal Master", "Create saved meals!",
    0, 0, new int[]{1, 5, 10, 25}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("nutrition-streak", "Consistent Logger", "Log food every day to build your streak!",
    0, 0, new int[]{3, 7, 30, 100}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("nutrition-under-goal", "Goal Crusher", "Stay under your calorie goal for the day!",
    0, 0, new int[]{3, 7, 21, 60}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("nutrition-goal-setter", "Goal Setter", "Set a calorie goal to track your nutrition!",
    0, 0, new int[]{0, 0, 0, 1}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

  //special trophies

    new Trophy("all-around", "All-Around Achiever", "Achieve at least one trophy from each PlotLine Category!", 
    0, 0, new int[]{0, 0, 0, 1}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("llm-investor", "Portfolio Pro", "Created a stock portfolio with the LLM!", 
    0, 0, new int[]{0, 0, 0, 1}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)), 

    new Trophy("first-profile-picture", "Picture Perfect", "Uploaded a profile picture!", 
    0, 0, new int[]{0, 0, 0, 1}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter)),

    new Trophy("getting-started", "Getting Started", "Finished the Get Started checklist!",
    0, 0, new int[]{0, 0, 0, 1}, ZonedDateTime.now(ZoneOffset.UTC).format(formatter))

  );


  private final S3Client s3Client;
  private final ObjectMapper objectMapper;
  private final ChatMessageService chatService;
  private final String bucketName = "plotline-database-bucket";

  public UserProfileService(S3Client s3Client,
                            ChatMessageService chatService) {
      this.s3Client = s3Client;
      this.objectMapper = new ObjectMapper();
      this.chatService = chatService;
  }

  public void saveProfile(UserProfile profile) {
      try {

          String user = objectMapper.writeValueAsString(profile);

          String username = normalize(profile.getUsername());
          String key = "users/" + username + "/profile.json";

          PutObjectRequest putRequest = PutObjectRequest.builder().
            bucket(bucketName).
            key(key).
            contentType("application/json").
            build();

            s3Client.putObject(putRequest, RequestBody.fromString(user));

      } catch (JsonProcessingException e) {
          log.error("contentType failed", e);
      }
  }

  /** The saved profile, or an empty one if the user hasn't saved theirs yet (new accounts). */
  public UserProfile getProfile(String username) throws IOException {
      String key = "users/" + normalize(username) + "/profile.json";
      GetObjectRequest getRequest = GetObjectRequest.builder()
        .bucket(bucketName)
        .key(key)
        .build();

      try {
        ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
        String userJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);
        return objectMapper.readValue(userJson, UserProfile.class);
      } catch (NoSuchKeyException e) {
        return new UserProfile(username, null, null, null);
      }
  }

  public String getPhoneNum(String username) {
      
    try {

      log.debug("{}", username);
      String key = "users/" + normalize(username) + "/account.json";

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
        String normUser = normalize(username);
        String fileName = "users/" + normUser + "/profile_pictures/" + normUser + ".jpg";

        log.debug("Uploading profile picture");

        PutObjectRequest putRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(fileName)
                .contentType(file.getContentType())
                .acl(ObjectCannedACL.PUBLIC_READ)
                .build();

        s3Client.putObject(putRequest, RequestBody.fromBytes(file.getBytes()));

        log.debug("Profile picture uploaded successfully");
        // first profile picture trophy awarded
        incrementTrophy(username, "first-profile-picture", 1);

        return profilePictureUrl(username);
  }

  /**
   * The picture's address, ending in its version ("?v=<time it was saved>"). The file is always
   * saved under the same name, so without the version the app kept showing the old picture from its
   * image cache after a new one was saved.
   */
  public String profilePictureUrl(String username) {
        String normUser = normalize(username);
        String key = "users/" + normUser + "/profile_pictures/" + normUser + ".jpg";
        String url = "https://" + bucketName + ".s3.amazonaws.com/" + key;
        try {
            Instant saved = s3Client.headObject(b -> b.bucket(bucketName).key(key)).lastModified();
            return saved == null ? url : url + "?v=" + saved.getEpochSecond();
        } catch (NoSuchKeyException e) {
            return url; // no picture yet: the app shows the placeholder
        } catch (S3Exception e) {
            if (e.statusCode() != 404) log.warn("Profile picture lookup failed ({})", e.toString());
            return url;
        }
  }

  // TROPHY FUNCTIONS

  public List<Trophy> getTrophies(String username) throws IOException {
    String key = "users/" + normalize(username) + "/trophies.json";

    try {
      GetObjectRequest getRequest = GetObjectRequest.builder()
      .bucket(bucketName)
      .key(key)
      .build();
      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
      String content = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

      // parse json into trophy
      List<Trophy> trophies = objectMapper.readValue(content, new TypeReference<List<Trophy>>() {});
      log.debug("Trophies: {}", trophies);

      // this trophy was created as "subcription-spender" but awarded as "subscription-spender", so it never counted
      boolean changed = false;
      for (Trophy trophy : trophies) {
        if ("subcription-spender".equals(trophy.getId())) {
          trophy.setId("subscription-spender");
          changed = true;
        }
      }
      // sleep tracking was an old feature: its trophies can't be earned any more
      changed |= trophies.removeIf(trophy -> trophy.getId().startsWith("sleep-"));
      if (changed) saveTrophies(username, trophies);

      // if new trophies were added since this user created their default trophies, add here
      if (!trophies.stream().map(Trophy::getId).collect(Collectors.toSet())
              .containsAll(DEFAULT_TROPHIES.stream().map(Trophy::getId).toList())) {
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
          log.debug("No trophies found for user: {}. Creating default trophies.", username);
          return createDefaultTrophies(username);
      } else {
          throw e;
      }
    }


  }

  public void saveTrophies(String username, List<Trophy> trophies) throws IOException {

    String key = "users/" + normalize(username) + "/trophies.json";
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
              announce(username, String.format("Earned the %s level of '%s' trophy!", levelName, trophy.getName()));
            }

            break;
        }
    }
    checkAllAround(username, trophies);
    saveTrophies(username, trophies);
    return trophies;
  }

  /**
   * All-Around Achiever: a trophy from every category. Checked after any trophy changes (it used to be
   * checked only when the loop above happened to pass it, so it was almost never awarded).
   */
  private void checkAllAround(String username, List<Trophy> trophies) {
    for (Trophy trophy : trophies) {
        if (trophy.getId().equals("all-around") && trophy.getLevel() == 0 && checkAllAroundAchiever(trophies)) {
            trophy.setLevel(4);
            trophy.setProgress(1);
            trophy.setEarnedDate(ZonedDateTime.now(ZoneOffset.UTC).format(formatter));
            announce(username, "Earned the 'All-Around Achiever' trophy!");
        }
    }
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
               trophyId.startsWith("subscription") || trophyId.startsWith("budget-pacer") ||
               trophyId.startsWith("monthly-spending") || trophyId.startsWith("healthy-eater") ||
               trophyId.startsWith("receipt") || trophyId.startsWith("llm-investor")) {
        return "budget";
    } else if (trophyId.startsWith("grocery") || trophyId.startsWith("meal-prepper")) {
        return "groceries";
    } else if (trophyId.startsWith("nutrition")) {
        return "nutrition";
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
        "goals", "calendar", "budget", "groceries", "nutrition"
    );
    return earnedCategories.containsAll(requiredCategories);
  }

  /**
   * Sets a trophy's progress to a count (e.g. how many subscriptions you have). A level reached for the
   * first time is announced like any other; going down and back up isn't announced again.
   */
  public void setTrophyProgress(String username, String trophyId, int newProgress) throws IOException {
    List<Trophy> trophies = getTrophies(username);
    for (Trophy trophy : trophies) {
        if (trophy.getId().equals(trophyId)) {
            int previousLevel = trophy.getLevel();
            trophy.setProgress(newProgress);
            int newLevel = 0;
            for (int i = 0; i < trophy.getThresholds().length; i++) {
                if (newProgress >= trophy.getThresholds()[i]) {
                    newLevel = i + 1;
                }
            }
            if (newLevel > previousLevel) {
                trophy.setEarnedDate(ZonedDateTime.now(ZoneOffset.UTC).format(formatter));
                announce(username, String.format("Earned the %s level of '%s' trophy!", LEVEL_NAMES[newLevel], trophy.getName()));
            }
            // keep the best level reached: removing a subscription doesn't take a trophy away
            trophy.setLevel(Math.max(previousLevel, newLevel));
            break;
        }
    }
    checkAllAround(username, trophies);
    saveTrophies(username, trophies);
}

  private static final String[] LEVEL_NAMES = {"", "Bronze", "Silver", "Gold", "Diamond"};

  /** "Earned the Gold level of …" in the person's chat */
  private void announce(String username, String content) {
    try {
        chatService.postMessage(username, new com.plotline.backend.dto.ChatMessage(null, username, null, content));
    } catch (JsonProcessingException e) {
        log.error("Trophy announcement failed", e); // the trophy itself is still saved
    }
  }

  
}
