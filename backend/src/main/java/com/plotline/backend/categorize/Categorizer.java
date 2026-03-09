package com.plotline.backend.categorize;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plaid.client.model.PersonalFinanceCategory;
import com.plaid.client.model.Transaction;
import com.plotline.backend.service.S3Service;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.*;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class Categorizer {
  private final UserCategoryStore userStore;
  private final S3Service s3Service;
  private final ObjectMapper objectMapper = new ObjectMapper();

  // Cache user categories to avoid repeated S3 calls (refreshed on sync)
  private final Map<String, Set<String>> userCategoriesCache = new ConcurrentHashMap<>();

  public Categorizer(UserCategoryStore store, S3Service s3Service) {
    this.userStore = store;
    this.s3Service = s3Service;
  }

  // Category type keywords - used to match against user's custom category names
  private static final String TYPE_GROCERY = "GROCERY";
  private static final String TYPE_DINING = "DINING";
  private static final String TYPE_GAS = "GAS";
  private static final String TYPE_TRANSPORT = "TRANSPORT";
  private static final String TYPE_SUBSCRIPTION = "SUBSCRIPTION";
  private static final String TYPE_ENTERTAINMENT = "ENTERTAINMENT";
  private static final String TYPE_UTILITIES = "UTILITIES";
  private static final String TYPE_RENT = "RENT";
  private static final String TYPE_SHOPPING = "SHOPPING";
  private static final String TYPE_MEDICAL = "MEDICAL";
  private static final String TYPE_GYM = "GYM";
  private static final String TYPE_TRAVEL = "TRAVEL";
  private static final String TYPE_PERSONAL = "PERSONAL";

  // Keywords for matching user categories to category types
  private static final Map<String, List<String>> TYPE_KEYWORDS = Map.ofEntries(
      Map.entry(TYPE_GROCERY, List.of("grocer", "food", "market", "supermarket")),
      Map.entry(TYPE_DINING, List.of("eating", "dining", "restaurant", "food out", "takeout", "delivery")),
      Map.entry(TYPE_GAS, List.of("gas", "fuel", "petrol")),
      Map.entry(TYPE_TRANSPORT, List.of("transport", "uber", "lyft", "ride", "commute", "transit", "parking")),
      Map.entry(TYPE_SUBSCRIPTION, List.of("subscription", "streaming", "membership")),
      Map.entry(TYPE_ENTERTAINMENT, List.of("entertainment", "fun", "leisure", "movie", "concert")),
      Map.entry(TYPE_UTILITIES, List.of("utilit", "electric", "water", "internet", "phone", "cable")),
      Map.entry(TYPE_RENT, List.of("rent", "mortgage", "housing")),
      Map.entry(TYPE_SHOPPING, List.of("shop", "cloth", "amazon", "retail", "store")),
      Map.entry(TYPE_MEDICAL, List.of("medic", "health", "doctor", "pharmacy", "drug")),
      Map.entry(TYPE_GYM, List.of("gym", "fitness", "workout", "exercise")),
      Map.entry(TYPE_TRAVEL, List.of("travel", "hotel", "flight", "vacation", "trip")),
      Map.entry(TYPE_PERSONAL, List.of("personal", "beauty", "hair", "spa"))
  );

  // Plaid detailed categories -> category type
  private static final Map<String, String> PLAID_DETAILED_TO_TYPE = Map.ofEntries(
      // Groceries
      Map.entry("FOOD_AND_DRINK_GROCERIES", TYPE_GROCERY),
      Map.entry("FOOD_AND_DRINK_SUPERSTORES", TYPE_GROCERY),
      Map.entry("GENERAL_MERCHANDISE_CONVENIENCE_STORES", TYPE_GROCERY),
      Map.entry("GENERAL_MERCHANDISE_SUPERSTORES", TYPE_GROCERY),

      // Dining/Eating Out
      Map.entry("FOOD_AND_DRINK_RESTAURANTS", TYPE_DINING),
      Map.entry("FOOD_AND_DRINK_FAST_FOOD", TYPE_DINING),
      Map.entry("FOOD_AND_DRINK_COFFEE", TYPE_DINING),
      Map.entry("FOOD_AND_DRINK_BEER_WINE_AND_LIQUOR", TYPE_DINING),
      Map.entry("FOOD_AND_DRINK_OTHER_FOOD_AND_DRINK", TYPE_DINING),

      // Gas
      Map.entry("TRANSPORTATION_GAS", TYPE_GAS),

      // Transportation
      Map.entry("TRANSPORTATION_PARKING", TYPE_TRANSPORT),
      Map.entry("TRANSPORTATION_PUBLIC_TRANSIT", TYPE_TRANSPORT),
      Map.entry("TRANSPORTATION_TAXIS_AND_RIDE_SHARES", TYPE_TRANSPORT),
      Map.entry("TRANSPORTATION_TOLLS", TYPE_TRANSPORT),
      Map.entry("TRANSPORTATION_OTHER_TRANSPORTATION", TYPE_TRANSPORT),

      // Subscriptions
      Map.entry("ENTERTAINMENT_MUSIC_AND_AUDIO", TYPE_SUBSCRIPTION),
      Map.entry("ENTERTAINMENT_TV_AND_MOVIES", TYPE_SUBSCRIPTION),

      // Entertainment
      Map.entry("ENTERTAINMENT_CASINOS_AND_GAMBLING", TYPE_ENTERTAINMENT),
      Map.entry("ENTERTAINMENT_SPORTING_EVENTS_AMUSEMENT_PARKS_AND_MUSEUMS", TYPE_ENTERTAINMENT),
      Map.entry("ENTERTAINMENT_VIDEO_GAMES", TYPE_ENTERTAINMENT),
      Map.entry("ENTERTAINMENT_OTHER_ENTERTAINMENT", TYPE_ENTERTAINMENT),
      Map.entry("RECREATION_OTHER_RECREATION", TYPE_ENTERTAINMENT),

      // Gym
      Map.entry("RECREATION_GYMS_AND_FITNESS_CENTERS", TYPE_GYM),
      Map.entry("PERSONAL_CARE_GYMS_AND_FITNESS_CENTERS", TYPE_GYM),

      // Utilities
      Map.entry("RENT_AND_UTILITIES_GAS_AND_ELECTRICITY", TYPE_UTILITIES),
      Map.entry("RENT_AND_UTILITIES_INTERNET_AND_CABLE", TYPE_UTILITIES),
      Map.entry("RENT_AND_UTILITIES_SEWAGE_AND_WASTE_MANAGEMENT", TYPE_UTILITIES),
      Map.entry("RENT_AND_UTILITIES_TELEPHONE", TYPE_UTILITIES),
      Map.entry("RENT_AND_UTILITIES_WATER", TYPE_UTILITIES),
      Map.entry("RENT_AND_UTILITIES_OTHER_UTILITIES", TYPE_UTILITIES),

      // Rent
      Map.entry("RENT_AND_UTILITIES_RENT", TYPE_RENT),

      // Shopping
      Map.entry("GENERAL_MERCHANDISE_CLOTHING_AND_ACCESSORIES", TYPE_SHOPPING),
      Map.entry("GENERAL_MERCHANDISE_DEPARTMENT_STORES", TYPE_SHOPPING),
      Map.entry("GENERAL_MERCHANDISE_ELECTRONICS", TYPE_SHOPPING),
      Map.entry("GENERAL_MERCHANDISE_ONLINE_MARKETPLACES", TYPE_SHOPPING),
      Map.entry("GENERAL_MERCHANDISE_OTHER_GENERAL_MERCHANDISE", TYPE_SHOPPING),

      // Medical
      Map.entry("MEDICAL_DENTAL_CARE", TYPE_MEDICAL),
      Map.entry("MEDICAL_EYE_CARE", TYPE_MEDICAL),
      Map.entry("MEDICAL_PHARMACIES_AND_SUPPLEMENTS", TYPE_MEDICAL),
      Map.entry("MEDICAL_PRIMARY_CARE", TYPE_MEDICAL),
      Map.entry("MEDICAL_OTHER_MEDICAL", TYPE_MEDICAL),

      // Travel
      Map.entry("TRAVEL_FLIGHTS", TYPE_TRAVEL),
      Map.entry("TRAVEL_LODGING", TYPE_TRAVEL),
      Map.entry("TRAVEL_RENTAL_CARS", TYPE_TRAVEL),
      Map.entry("TRANSPORTATION_AIRLINES_AND_AVIATION_SERVICES", TYPE_TRAVEL),

      // Personal Care
      Map.entry("PERSONAL_CARE_HAIR_AND_BEAUTY", TYPE_PERSONAL),
      Map.entry("PERSONAL_CARE_LAUNDRY_AND_DRY_CLEANING", TYPE_PERSONAL),
      Map.entry("PERSONAL_CARE_OTHER_PERSONAL_CARE", TYPE_PERSONAL)
  );

  // Plaid primary categories -> category type (fallback if detailed not found)
  private static final Map<String, String> PLAID_PRIMARY_TO_TYPE = Map.ofEntries(
      Map.entry("FOOD_AND_DRINK", TYPE_DINING), // Default food to dining; grocery stores handled by merchant rules
      Map.entry("TRANSPORTATION", TYPE_TRANSPORT),
      Map.entry("RENT_AND_UTILITIES", TYPE_UTILITIES),
      Map.entry("ENTERTAINMENT", TYPE_ENTERTAINMENT),
      Map.entry("RECREATION", TYPE_ENTERTAINMENT),
      Map.entry("GENERAL_MERCHANDISE", TYPE_SHOPPING),
      Map.entry("MEDICAL", TYPE_MEDICAL),
      Map.entry("TRAVEL", TYPE_TRAVEL),
      Map.entry("PERSONAL_CARE", TYPE_PERSONAL)
  );

  // Merchant name patterns -> category type (checked FIRST before Plaid categories)
  private static final List<MerchantRule> MERCHANT_RULES = List.of(
      // Grocery stores - MUST be checked before dining
      new MerchantRule("WEGMANS", TYPE_GROCERY),
      new MerchantRule("WHOLE FOODS", TYPE_GROCERY),
      new MerchantRule("TRADER JOE", TYPE_GROCERY),
      new MerchantRule("SAFEWAY", TYPE_GROCERY),
      new MerchantRule("KROGER", TYPE_GROCERY),
      new MerchantRule("PUBLIX", TYPE_GROCERY),
      new MerchantRule("ALDI", TYPE_GROCERY),
      new MerchantRule("COSTCO", TYPE_GROCERY),
      new MerchantRule("SAM'S CLUB", TYPE_GROCERY),
      new MerchantRule("SAMS CLUB", TYPE_GROCERY),
      new MerchantRule("TARGET", TYPE_GROCERY),
      new MerchantRule("WALMART", TYPE_GROCERY),
      new MerchantRule("GIANT", TYPE_GROCERY),
      new MerchantRule("STOP & SHOP", TYPE_GROCERY),
      new MerchantRule("STOP AND SHOP", TYPE_GROCERY),
      new MerchantRule("FOOD LION", TYPE_GROCERY),
      new MerchantRule("HARRIS TEETER", TYPE_GROCERY),
      new MerchantRule("HEB ", TYPE_GROCERY),
      new MerchantRule("H-E-B", TYPE_GROCERY),
      new MerchantRule("MEIJER", TYPE_GROCERY),
      new MerchantRule("SPROUTS", TYPE_GROCERY),
      new MerchantRule("FRESH MARKET", TYPE_GROCERY),
      new MerchantRule("MARKET BASKET", TYPE_GROCERY),
      new MerchantRule("SHOPRITE", TYPE_GROCERY),
      new MerchantRule("WINN DIXIE", TYPE_GROCERY),
      new MerchantRule("WINN-DIXIE", TYPE_GROCERY),
      new MerchantRule("ACME MARKET", TYPE_GROCERY),
      new MerchantRule("JEWEL-OSCO", TYPE_GROCERY),
      new MerchantRule("VONS", TYPE_GROCERY),
      new MerchantRule("RALPHS", TYPE_GROCERY),
      new MerchantRule("ALBERTSON", TYPE_GROCERY),
      new MerchantRule("PIGGLY WIGGLY", TYPE_GROCERY),
      new MerchantRule("WINCO", TYPE_GROCERY),
      new MerchantRule("EREWHON", TYPE_GROCERY),
      new MerchantRule("INSTACART", TYPE_GROCERY),

      // Gas stations
      new MerchantRule("SHELL", TYPE_GAS),
      new MerchantRule("EXXON", TYPE_GAS),
      new MerchantRule("CHEVRON", TYPE_GAS),
      new MerchantRule("BP ", TYPE_GAS),
      new MerchantRule("MOBIL", TYPE_GAS),
      new MerchantRule("SUNOCO", TYPE_GAS),
      new MerchantRule("CITGO", TYPE_GAS),
      new MerchantRule("SPEEDWAY", TYPE_GAS),
      new MerchantRule("RACETRAC", TYPE_GAS),
      new MerchantRule("QUIKTRIP", TYPE_GAS),
      new MerchantRule("GETGO", TYPE_GAS),
      new MerchantRule("MARATHON", TYPE_GAS),
      new MerchantRule("VALERO", TYPE_GAS),
      new MerchantRule("CASEY", TYPE_GAS),
      new MerchantRule("PILOT", TYPE_GAS),
      new MerchantRule("LOVES TRAVEL", TYPE_GAS),
      new MerchantRule("FLYING J", TYPE_GAS),

      // Dining - fast food and restaurants
      new MerchantRule("STARBUCKS", TYPE_DINING),
      new MerchantRule("MCDONALD", TYPE_DINING),
      new MerchantRule("CHIPOTLE", TYPE_DINING),
      new MerchantRule("CHICK-FIL-A", TYPE_DINING),
      new MerchantRule("CHICKFILA", TYPE_DINING),
      new MerchantRule("TACO BELL", TYPE_DINING),
      new MerchantRule("WENDY'S", TYPE_DINING),
      new MerchantRule("WENDYS", TYPE_DINING),
      new MerchantRule("BURGER KING", TYPE_DINING),
      new MerchantRule("SUBWAY", TYPE_DINING),
      new MerchantRule("DUNKIN", TYPE_DINING),
      new MerchantRule("PANERA", TYPE_DINING),
      new MerchantRule("DOMINO", TYPE_DINING),
      new MerchantRule("PIZZA HUT", TYPE_DINING),
      new MerchantRule("PAPA JOHN", TYPE_DINING),
      new MerchantRule("PANDA EXPRESS", TYPE_DINING),
      new MerchantRule("KFC", TYPE_DINING),
      new MerchantRule("POPEYE", TYPE_DINING),
      new MerchantRule("FIVE GUYS", TYPE_DINING),
      new MerchantRule("SHAKE SHACK", TYPE_DINING),
      new MerchantRule("IN-N-OUT", TYPE_DINING),
      new MerchantRule("DOORDASH", TYPE_DINING),
      new MerchantRule("UBER EATS", TYPE_DINING),
      new MerchantRule("UBEREATS", TYPE_DINING),
      new MerchantRule("GRUBHUB", TYPE_DINING),
      new MerchantRule("POSTMATES", TYPE_DINING),
      new MerchantRule("SEAMLESS", TYPE_DINING),
      new MerchantRule("WAWA", TYPE_DINING),
      new MerchantRule("SHEETZ", TYPE_DINING),

      // Transportation
      new MerchantRule("UBER ", TYPE_TRANSPORT),
      new MerchantRule("LYFT", TYPE_TRANSPORT),

      // Subscriptions
      new MerchantRule("SPOTIFY", TYPE_SUBSCRIPTION),
      new MerchantRule("NETFLIX", TYPE_SUBSCRIPTION),
      new MerchantRule("HULU", TYPE_SUBSCRIPTION),
      new MerchantRule("DISNEY+", TYPE_SUBSCRIPTION),
      new MerchantRule("DISNEY PLUS", TYPE_SUBSCRIPTION),
      new MerchantRule("HBO", TYPE_SUBSCRIPTION),
      new MerchantRule("APPLE.COM/BILL", TYPE_SUBSCRIPTION),
      new MerchantRule("APPLE MUSIC", TYPE_SUBSCRIPTION),
      new MerchantRule("AMAZON PRIME", TYPE_SUBSCRIPTION),
      new MerchantRule("YOUTUBE PREMIUM", TYPE_SUBSCRIPTION),
      new MerchantRule("YOUTUBE MUSIC", TYPE_SUBSCRIPTION),
      new MerchantRule("AUDIBLE", TYPE_SUBSCRIPTION),
      new MerchantRule("PARAMOUNT", TYPE_SUBSCRIPTION),
      new MerchantRule("PEACOCK", TYPE_SUBSCRIPTION),
      new MerchantRule("MAX ", TYPE_SUBSCRIPTION),

      // Gym
      new MerchantRule("PLANET FITNESS", TYPE_GYM),
      new MerchantRule("ANYTIME FITNESS", TYPE_GYM),
      new MerchantRule("LA FITNESS", TYPE_GYM),
      new MerchantRule("GOLD'S GYM", TYPE_GYM),
      new MerchantRule("GOLDS GYM", TYPE_GYM),
      new MerchantRule("EQUINOX", TYPE_GYM),
      new MerchantRule("ORANGETHEORY", TYPE_GYM),
      new MerchantRule("CROSSFIT", TYPE_GYM),
      new MerchantRule("YMCA", TYPE_GYM),
      new MerchantRule("24 HOUR FITNESS", TYPE_GYM),

      // Medical/Pharmacy
      new MerchantRule("CVS", TYPE_MEDICAL),
      new MerchantRule("WALGREEN", TYPE_MEDICAL),
      new MerchantRule("RITE AID", TYPE_MEDICAL)
  );

  private record MerchantRule(String pattern, String type) {}

  /**
   * Main categorization method - maps a transaction to a user's budget category.
   */
  public String map(String username, Transaction t) {
    String merchant = (t.getMerchantName() != null ? t.getMerchantName() : t.getName());
    String m = merchant == null ? "" : merchant.toUpperCase().trim();

    // 1. Check user's explicit merchant overrides first
    String userOverride = userStore.lookup(username, m);
    if (userOverride != null && !userOverride.isBlank()) {
      System.out.println("  → User override for '" + m + "' = " + userOverride);
      return userOverride;
    }

    // Load user's categories
    Set<String> userCategories = getUserCategories(username);

    // 2. Check merchant rules (grocery stores, gas stations, etc.)
    for (MerchantRule rule : MERCHANT_RULES) {
      if (m.contains(rule.pattern)) {
        String matched = findBestUserCategory(rule.type, userCategories);
        if (matched != null) {
          System.out.println("  → Merchant '" + m + "' matched rule " + rule.pattern + " → " + matched);
          return matched;
        }
      }
    }

    // 3. Check Plaid detailed category
    PersonalFinanceCategory pfc = t.getPersonalFinanceCategory();
    if (pfc != null) {
      String detailed = pfc.getDetailed();
      if (detailed != null && !detailed.isBlank()) {
        String type = PLAID_DETAILED_TO_TYPE.get(detailed);
        if (type != null) {
          String matched = findBestUserCategory(type, userCategories);
          if (matched != null) {
            System.out.println("  → Plaid detailed '" + detailed + "' → " + matched);
            return matched;
          }
        }
      }

      // 4. Fall back to Plaid primary category
      String primary = pfc.getPrimary();
      if (primary != null && !primary.isBlank()) {
        String type = PLAID_PRIMARY_TO_TYPE.get(primary);
        if (type != null) {
          String matched = findBestUserCategory(type, userCategories);
          if (matched != null) {
            System.out.println("  → Plaid primary '" + primary + "' → " + matched);
            return matched;
          }
        }
      }
    }

    System.out.println("  → No category match for '" + m + "', returning Uncategorized");
    return "Uncategorized";
  }

  /**
   * Find the best matching user category for a given category type.
   */
  private String findBestUserCategory(String type, Set<String> userCategories) {
    if (userCategories == null || userCategories.isEmpty()) {
      return getDefaultCategory(type);
    }

    List<String> keywords = TYPE_KEYWORDS.get(type);
    if (keywords == null) {
      return getDefaultCategory(type);
    }

    // Look for a user category that contains any of the keywords
    for (String userCat : userCategories) {
      String lower = userCat.toLowerCase();
      for (String keyword : keywords) {
        if (lower.contains(keyword)) {
          return userCat;
        }
      }
    }

    // No fuzzy match found - return default
    return getDefaultCategory(type);
  }

  /**
   * Default category names when user doesn't have a matching custom category.
   */
  private String getDefaultCategory(String type) {
    return switch (type) {
      case TYPE_GROCERY -> "Groceries";
      case TYPE_DINING -> "Eating Out";
      case TYPE_GAS -> "Gas";
      case TYPE_TRANSPORT -> "Transportation";
      case TYPE_SUBSCRIPTION -> "Subscriptions";
      case TYPE_ENTERTAINMENT -> "Entertainment";
      case TYPE_UTILITIES -> "Utilities";
      case TYPE_RENT -> "Rent";
      case TYPE_SHOPPING -> "Shopping";
      case TYPE_MEDICAL -> "Medical";
      case TYPE_GYM -> "Gym";
      case TYPE_TRAVEL -> "Travel";
      case TYPE_PERSONAL -> "Personal Care";
      default -> "Other";
    };
  }

  /**
   * Load user's budget categories from S3.
   */
  private Set<String> getUserCategories(String username) {
    // Check cache first
    if (userCategoriesCache.containsKey(username)) {
      return userCategoriesCache.get(username);
    }

    Set<String> categories = new HashSet<>();
    try {
      // Try weekly budget first, then monthly
      String key = String.format("users/%s/weekly-budget-edited.json", username.toLowerCase());
      byte[] data = s3Service.downloadFile(key);
      if (data != null) {
        Map<String, Object> budget = objectMapper.readValue(data, new TypeReference<>() {});
        // Budget structure could be { "budget": { "category": amount } } or just { "category": amount }
        Object budgetMap = budget.get("budget");
        if (budgetMap instanceof Map) {
          categories.addAll(((Map<String, ?>) budgetMap).keySet());
        } else {
          categories.addAll(budget.keySet());
        }
      }
    } catch (Exception e) {
      // Try monthly as fallback
      try {
        String key = String.format("users/%s/monthly-budget-edited.json", username.toLowerCase());
        byte[] data = s3Service.downloadFile(key);
        if (data != null) {
          Map<String, Object> budget = objectMapper.readValue(data, new TypeReference<>() {});
          Object budgetMap = budget.get("budget");
          if (budgetMap instanceof Map) {
            categories.addAll(((Map<String, ?>) budgetMap).keySet());
          } else {
            categories.addAll(budget.keySet());
          }
        }
      } catch (Exception ex) {
        // No budget found - will use defaults
      }
    }

    // Remove non-category keys
    categories.remove("username");
    categories.remove("type");

    userCategoriesCache.put(username, categories);
    System.out.println("Loaded " + categories.size() + " categories for user " + username + ": " + categories);
    return categories;
  }

  /**
   * Clear cached categories for a user (call this when budget is updated).
   */
  public void clearCategoryCache(String username) {
    userCategoriesCache.remove(username);
  }

  // Minimal override controller colocated for brevity
  @RestController
  @RequestMapping("/api/category")
  public static class CategoryController {
    private final UserCategoryStore store;
    public CategoryController(UserCategoryStore store){ this.store = store; }

    @PostMapping("/override")
    public Map<String,Object> override(@RequestBody Map<String,String> body) {
      String username = body.get("username");
      String merchant = body.get("merchant") == null ? "" : body.get("merchant").toUpperCase().trim();
      String category = body.get("category");
      store.saveOverride(username, merchant, category);
      return Map.of("ok", true);
    }
  }
}
