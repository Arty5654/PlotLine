package com.plotline.backend.categorize;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

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
    private static final Logger log = LoggerFactory.getLogger(Categorizer.class);

  private final UserCategoryStore userStore;
  private final S3Service s3Service;
  private final MerchantCategoryAI aiCategories;
  private final ObjectMapper objectMapper = new ObjectMapper();

  // Cache user categories to avoid repeated S3 calls (refreshed on sync)
  private final Map<String, Set<String>> userCategoriesCache = new ConcurrentHashMap<>();

  public Categorizer(UserCategoryStore store, S3Service s3Service, MerchantCategoryAI aiCategories) {
    this.userStore = store;
    this.s3Service = s3Service;
    this.aiCategories = aiCategories;
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
  // more of the bank's categories, so less ends up in Miscellaneous
  private static final String TYPE_PHONE = "PHONE";
  private static final String TYPE_INSURANCE = "INSURANCE";
  private static final String TYPE_CAR_INSURANCE = "CAR_INSURANCE";
  private static final String TYPE_TAXES = "TAXES";
  private static final String TYPE_CAR_MAINTENANCE = "CAR_MAINTENANCE";
  private static final String TYPE_HOME = "HOME";
  private static final String TYPE_GIFTS = "GIFTS";
  private static final String TYPE_EDUCATION = "EDUCATION";
  private static final String TYPE_CHILDCARE = "CHILDCARE";
  private static final String TYPE_SERVICES = "SERVICES";
  private static final String TYPE_PETS = "PETS";

  private static final List<String> ALL_TYPES = List.of(TYPE_GROCERY, TYPE_DINING, TYPE_GAS, TYPE_TRANSPORT, TYPE_SUBSCRIPTION,
      TYPE_ENTERTAINMENT, TYPE_UTILITIES, TYPE_RENT, TYPE_SHOPPING, TYPE_MEDICAL, TYPE_GYM, TYPE_TRAVEL, TYPE_PERSONAL,
      TYPE_PHONE, TYPE_INSURANCE, TYPE_CAR_INSURANCE, TYPE_TAXES, TYPE_CAR_MAINTENANCE, TYPE_HOME, TYPE_GIFTS, TYPE_EDUCATION,
      TYPE_CHILDCARE, TYPE_SERVICES, TYPE_PETS);

  /** when a user's budget has nothing for a type, try this one before the standard name (a phone bill → Utilities) */
  private static final Map<String, String> FALLBACK_TYPE = Map.of(
      TYPE_PHONE, TYPE_UTILITIES,
      TYPE_CAR_INSURANCE, TYPE_INSURANCE);

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
      Map.entry(TYPE_PERSONAL, List.of("personal", "beauty", "hair", "spa")),
      Map.entry(TYPE_PHONE, List.of("phone", "cell", "mobile", "wireless")),
      Map.entry(TYPE_INSURANCE, List.of("insurance")),
      Map.entry(TYPE_CAR_INSURANCE, List.of("car insurance", "auto insurance", "car ins")),
      Map.entry(TYPE_TAXES, List.of("tax", "fees")),          // "fees", not "fee": Coffee
      Map.entry(TYPE_CAR_MAINTENANCE, List.of("car maint", "car care", "car repair", "car service")),
      Map.entry(TYPE_HOME, List.of("home", "house", "furniture")),
      Map.entry(TYPE_GIFTS, List.of("gift", "donat", "charit")),
      Map.entry(TYPE_EDUCATION, List.of("educat", "school", "tuition", "class")),
      Map.entry(TYPE_CHILDCARE, List.of("childcare", "child care", "daycare", "babysit")),
      Map.entry(TYPE_SERVICES, List.of()),                    // only "Services" itself: "Streaming Services" isn't one
      Map.entry(TYPE_PETS, List.of("pet", "vet"))
  );

  // Plaid detailed categories -> category type
  private static final Map<String, String> PLAID_DETAILED_TO_TYPE = Map.ofEntries(
      // Groceries
      Map.entry("FOOD_AND_DRINK_GROCERIES", TYPE_GROCERY),
      Map.entry("FOOD_AND_DRINK_SUPERSTORES", TYPE_GROCERY),
      Map.entry("GENERAL_MERCHANDISE_CONVENIENCE_STORES", TYPE_GROCERY),
      Map.entry("GENERAL_MERCHANDISE_SUPERSTORES", TYPE_GROCERY),

      // Dining/Eating Out
      Map.entry("FOOD_AND_DRINK_RESTAURANT", TYPE_DINING),
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
      Map.entry("RENT_AND_UTILITIES_TELEPHONE", TYPE_PHONE),
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

      // Shopping, a few more
      Map.entry("GENERAL_MERCHANDISE_BOOKSTORES_AND_NEWSSTANDS", TYPE_SHOPPING),
      Map.entry("GENERAL_MERCHANDISE_DISCOUNT_STORES", TYPE_SHOPPING),
      Map.entry("GENERAL_MERCHANDISE_OFFICE_SUPPLIES", TYPE_SHOPPING),
      Map.entry("GENERAL_MERCHANDISE_SPORTING_GOODS", TYPE_SHOPPING),
      Map.entry("GENERAL_MERCHANDISE_TOBACCO_AND_VAPE", TYPE_SHOPPING),
      Map.entry("GENERAL_MERCHANDISE_GIFTS_AND_NOVELTIES", TYPE_GIFTS),
      Map.entry("GENERAL_MERCHANDISE_PET_SUPPLIES", TYPE_PETS),
      Map.entry("MEDICAL_VETERINARY_SERVICES", TYPE_PETS),

      // Services (they all used to be Miscellaneous)
      Map.entry("GENERAL_SERVICES_AUTOMOTIVE", TYPE_CAR_MAINTENANCE),
      Map.entry("GENERAL_SERVICES_CHILDCARE", TYPE_CHILDCARE),
      Map.entry("GENERAL_SERVICES_EDUCATION", TYPE_EDUCATION),
      Map.entry("GENERAL_SERVICES_INSURANCE", TYPE_INSURANCE),
      Map.entry("GENERAL_SERVICES_ACCOUNTING_AND_FINANCIAL_PLANNING", TYPE_SERVICES),
      Map.entry("GENERAL_SERVICES_CONSULTING_AND_LEGAL", TYPE_SERVICES),
      Map.entry("GENERAL_SERVICES_POSTAGE_AND_SHIPPING", TYPE_SERVICES),
      Map.entry("GENERAL_SERVICES_STORAGE", TYPE_SERVICES),
      Map.entry("GENERAL_SERVICES_OTHER_GENERAL_SERVICES", TYPE_SERVICES),

      // Home improvement
      Map.entry("HOME_IMPROVEMENT_FURNITURE", TYPE_HOME),
      Map.entry("HOME_IMPROVEMENT_HARDWARE", TYPE_HOME),
      Map.entry("HOME_IMPROVEMENT_REPAIR_AND_MAINTENANCE", TYPE_HOME),
      Map.entry("HOME_IMPROVEMENT_SECURITY", TYPE_HOME),
      Map.entry("HOME_IMPROVEMENT_OTHER_HOME_IMPROVEMENT", TYPE_HOME),

      // Government and giving
      Map.entry("GOVERNMENT_AND_NON_PROFIT_DONATIONS", TYPE_GIFTS),
      Map.entry("GOVERNMENT_AND_NON_PROFIT_GOVERNMENT_DEPARTMENTS_AND_AGENCIES", TYPE_TAXES),
      Map.entry("GOVERNMENT_AND_NON_PROFIT_TAX_PAYMENT", TYPE_TAXES),
      Map.entry("GOVERNMENT_AND_NON_PROFIT_OTHER_GOVERNMENT_AND_NON_PROFIT", TYPE_TAXES),

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
      Map.entry("PERSONAL_CARE", TYPE_PERSONAL),
      Map.entry("GENERAL_SERVICES", TYPE_SERVICES),
      Map.entry("HOME_IMPROVEMENT", TYPE_HOME),
      Map.entry("GOVERNMENT_AND_NON_PROFIT", TYPE_TAXES)
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

      // Car insurance (the bank only says "insurance")
      new MerchantRule("GEICO", TYPE_CAR_INSURANCE),
      new MerchantRule("PROGRESSIVE", TYPE_CAR_INSURANCE),
      new MerchantRule("STATE FARM", TYPE_CAR_INSURANCE),
      new MerchantRule("ALLSTATE", TYPE_CAR_INSURANCE),
      new MerchantRule("LIBERTY MUTUAL", TYPE_CAR_INSURANCE),
      new MerchantRule("ERIE INSURANCE", TYPE_CAR_INSURANCE),

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
    return map(username, t, getUserCategories(username));
  }

  /**
   * The standard category ("Groceries", "Eating Out", "Gas", ...) whatever the user's own budget
   * categories are: the budget quiz uses it to show real spending before there's a budget.
   */
  public String mapToStandard(String username, Transaction t) {
    return map(username, t, Set.of());
  }

  private static final Set<String> NOT_SPENDING = Set.of("TRANSFER_IN", "TRANSFER_OUT", "LOAN_PAYMENTS", "INCOME", "BANK_FEES");

  /** the standard names the AI picks from for merchants the bank couldn't label */
  public static List<String> standardNames() {
    List<String> names = new ArrayList<>(ALL_TYPES.stream().map(Categorizer::defaultName).toList());
    names.add("Miscellaneous");
    return names;
  }

  /**
   * Before mapping a batch: merchants nothing else can sort are asked about once (OpenAI, remembered
   * per user), so they don't all end up in Miscellaneous.
   */
  public void prepare(String username, Collection<Transaction> transactions) {
    List<String> unknown = transactions.stream()
        // only spending: never money moving between people or accounts, pay, or loan payments
        .filter(t -> t.getAmount() != null && t.getAmount() > 0 && !Boolean.TRUE.equals(t.getPending()))
        .filter(t -> t.getPersonalFinanceCategory() == null || !NOT_SPENDING.contains(t.getPersonalFinanceCategory().getPrimary()))
        .filter(t -> broadByRules(t) == null && userStore.lookup(username, merchantKey(t)) == null)
        .map(Categorizer::merchantKey).filter(m -> !m.isBlank()).distinct().toList();
    if (!unknown.isEmpty()) aiCategories.classify(username, unknown, standardNames());
    // narrower categories (a bar out of Eating Out) for places their bank label and name don't place
    Map<String, List<String>> nicheOptions = new LinkedHashMap<>();
    for (Transaction t : transactions) {
      if (t.getAmount() == null || t.getAmount() <= 0 || Boolean.TRUE.equals(t.getPending())) continue;
      if (t.getPersonalFinanceCategory() != null && NOT_SPENDING.contains(t.getPersonalFinanceCategory().getPrimary())) continue;
      String m = merchantKey(t);
      if (m.isBlank() || nicheOptions.containsKey(m) || userStore.lookup(username, m) != null) continue;
      Broad broad = broad(username, t);
      if (broad == null) continue;
      List<String> options = NicheCategories.optionsFor(broad.type());
      String detailed = t.getPersonalFinanceCategory() != null ? t.getPersonalFinanceCategory().getDetailed() : null;
      if (!options.isEmpty() && NicheCategories.matching(detailed, m, broad.type()).isEmpty()) nicheOptions.put(m, options);
    }
    if (!nicheOptions.isEmpty()) aiCategories.classifyNiches(username, nicheOptions, NicheCategories.MEANING);
    // their own categories PlotLine has no rule for: which merchants belong there (most won't)
    List<String> custom = customCategories(getUserCategories(username));
    if (!custom.isEmpty()) {
      List<String> merchants = transactions.stream()
          .filter(t -> t.getAmount() != null && t.getAmount() > 0 && !Boolean.TRUE.equals(t.getPending()))
          .filter(t -> t.getPersonalFinanceCategory() == null || !NOT_SPENDING.contains(t.getPersonalFinanceCategory().getPrimary()))
          .map(Categorizer::merchantKey).filter(m -> !m.isBlank()).distinct().toList();
      aiCategories.classifyCustom(username, merchants, custom);
    }
  }

  private static String merchantKey(Transaction t) {
    String merchant = (t.getMerchantName() != null ? t.getMerchantName() : t.getName());
    return merchant == null ? "" : merchant.toUpperCase().trim();
  }

  /**
   * A category and how it was picked, so people can see why: "yours" (a rule they set), "store" (a
   * store PlotLine knows), "bank" (the bank's own label), "ai" (sorted by AI from the name), "none".
   */
  public record Sorted(String category, String how) { }

  private static final Sorted NONE = new Sorted("Uncategorized", "none");

  /** the standard category and how it was picked (the quiz's "see how your spending was sorted") */
  public Sorted sortToStandard(String username, Transaction t) {
    return sort(username, t, Set.of());
  }

  private String map(String username, Transaction t, Set<String> userCategories) {
    return sort(username, t, userCategories).category();
  }

  private Sorted sort(String username, Transaction t, Set<String> userCategories) {
    String m = merchantKey(t);
    // 1. their own rule for this merchant
    String userOverride = userStore.lookup(username, m);
    if (userOverride != null && !userOverride.isBlank()) {
      log.debug(" → User override for '{}' = {}", m, userOverride);
      return new Sorted(userOverride, "yours");
    }
    Broad broad = broad(username, t);
    // 2. a narrower category of theirs (Alcohol & Bars rather than Eating Out), or one of their own the AI matched
    if (userCategories != null && !userCategories.isEmpty()) {
      Sorted specific = specific(username, t, m, broad, userCategories);
      if (specific != null) return specific;
    }
    // 3. the broad category
    if (broad == null) {
      log.debug(" → No category match for '{}', returning Uncategorized", m);
      return NONE;
    }
    return new Sorted(findBestUserCategory(broad.type(), userCategories), broad.how());
  }

  /** the broad type and how it was picked: a known store, the bank's label, or the AI from the name */
  private record Broad(String type, String how) { }

  private Broad broad(String username, Transaction t) {
    Broad byRules = broadByRules(t);
    if (byRules != null) return byRules;
    // what the AI said about this merchant (see prepare)
    String ai = aiCategories.lookup(username, merchantKey(t));
    String type = ai == null ? null : ALL_TYPES.stream().filter(ty -> defaultName(ty).equals(ai)).findFirst().orElse(null);
    return type == null ? null : new Broad(type, "ai");
  }

  private Broad broadByRules(Transaction t) {
    String m = merchantKey(t);
    // merchant rules (grocery stores, gas stations, etc.)
    for (MerchantRule rule : MERCHANT_RULES) {
      if (m.contains(rule.pattern)) return new Broad(rule.type, "store");
    }
    PersonalFinanceCategory pfc = t.getPersonalFinanceCategory();
    if (pfc != null) {
      // the bank's detailed label, then its broad one
      String type = pfc.getDetailed() == null ? null : PLAID_DETAILED_TO_TYPE.get(pfc.getDetailed());
      if (type == null && pfc.getPrimary() != null) type = PLAID_PRIMARY_TO_TYPE.get(pfc.getPrimary());
      if (type != null) return new Broad(type, "bank");
    }
    return null;
  }

  private Sorted specific(String username, Transaction t, String merchant, Broad broad, Set<String> userCategories) {
    if (broad != null) {
      Map<NicheCategories.Niche, String> mine = new HashMap<>();
      for (String c : new TreeSet<>(userCategories)) {
        NicheCategories.Niche n = nicheOf(c);
        if (n != null) mine.putIfAbsent(n, c);
      }
      if (!mine.isEmpty()) {
        String detailed = t.getPersonalFinanceCategory() != null ? t.getPersonalFinanceCategory().getDetailed() : null;
        for (NicheCategories.Match match : NicheCategories.matching(detailed, merchant, broad.type(), aiCategories.lookupNiche(username, merchant))) {
          String theirs = mine.get(match.niche());
          if (theirs != null) return new Sorted(theirs, match.how());
        }
      }
    }
    String custom = aiCategories.lookupCustom(username, merchant);
    if (custom != null) {
      for (String c : userCategories) if (c.equalsIgnoreCase(custom)) return new Sorted(c, "ai");
    }
    return null;
  }

  /**
   * Where it would go without their narrower or own categories (Subscriptions for a Netflix charge, even
   * with Streaming Services). When that's a fixed cost, the fixed amount already counts it.
   */
  public String mapBroad(String username, Transaction t) {
    String userOverride = userStore.lookup(username, merchantKey(t));
    if (userOverride != null && !userOverride.isBlank()) return userOverride;
    Broad broad = broad(username, t);
    return broad == null ? null : findBestUserCategory(broad.type(), getUserCategories(username));
  }

  /** the narrower category a budget category is (Alcohol & Bars, Parking...), or null for a broad one or their own */
  static NicheCategories.Niche nicheOf(String category) {
    if (category == null || isStandardName(category)) return null;
    NicheCategories.Niche n = NicheCategories.named(category);
    return n == null || NicheCategories.broadByName(category, n) ? null : n;
  }

  private static boolean isStandardName(String category) {
    String c = category.strip();
    return ALL_TYPES.stream().anyMatch(ty -> defaultName(ty).equalsIgnoreCase(c));
  }

  /** money set aside or owed, not spent at a store: never a place to sort purchases into */
  private static final java.util.regex.Pattern NOT_A_PURCHASE = java.util.regex.Pattern.compile(
      "\\bfund\\b|saving|invest|\\bira\\b|401|\\bhsa\\b|debt|loan|payment|miscellaneous|^other$", java.util.regex.Pattern.CASE_INSENSITIVE);

  /** their own categories PlotLine has no rule for ("Golf", "Date Night"): the AI matches merchants to them */
  static List<String> customCategories(Set<String> userCategories) {
    List<String> out = new ArrayList<>();
    for (String c : new TreeSet<>(userCategories)) {
      if (c == null || c.isBlank() || isStandardName(c) || nicheOf(c) != null || NicheCategories.named(c) != null) continue;
      if (com.plotline.backend.service.FixedCosts.fromQuiz(c) || NOT_A_PURCHASE.matcher(c).find()) continue;
      String lower = c.toLowerCase();
      boolean known = TYPE_KEYWORDS.values().stream().flatMap(List::stream).anyMatch(lower::contains);
      if (!known) out.add(c);
    }
    return out;
  }

  /**
   * The narrower categories (by their app names) a transaction would go to if the budget had them,
   * best first: the quiz shows what switching one on would move out of the broad category.
   */
  public List<String> nichesFor(String username, Transaction t) {
    String m = merchantKey(t);
    String userOverride = userStore.lookup(username, m);
    if (userOverride != null && !userOverride.isBlank()) return List.of();
    Broad broad = broad(username, t);
    if (broad == null) return List.of();
    String detailed = t.getPersonalFinanceCategory() != null ? t.getPersonalFinanceCategory().getDetailed() : null;
    return NicheCategories.matching(detailed, m, broad.type(), aiCategories.lookupNiche(username, m)).stream().map(x -> x.niche().name()).toList();
  }

  /**
   * Find the best matching user category for a given category type.
   */
  private String findBestUserCategory(String type, Set<String> userCategories) {
    if (userCategories == null || userCategories.isEmpty()) {
      return getDefaultCategory(type);
    }
    String own = ownCategory(type, userCategories);
    if (own != null) return own;
    // nothing for it in their budget: a close type they do have (a phone bill → Utilities)
    String fallback = FALLBACK_TYPE.get(type);
    if (fallback != null) {
      String close = ownCategory(fallback, userCategories);
      if (close != null) return close;
    }
    return getDefaultCategory(type);
  }

  /** their category with the type's own name, else the first (alphabetically, so it's always the same) with a keyword */
  private String ownCategory(String type, Set<String> userCategories) {
    String standard = getDefaultCategory(type);
    for (String userCat : userCategories) {
      if (userCat.equalsIgnoreCase(standard)) return userCat;
    }
    List<String> keywords = TYPE_KEYWORDS.getOrDefault(type, List.of());
    for (String userCat : new TreeSet<>(userCategories)) {
      if (nicheOf(userCat) != null) continue; // Clothing gets clothes, not all of Shopping
      String lower = userCat.toLowerCase();
      for (String keyword : keywords) {
        if (lower.contains(keyword)) return userCat;
      }
    }
    return null;
  }

  /**
   * Default category names when user doesn't have a matching custom category.
   */
  private String getDefaultCategory(String type) {
    return defaultName(type);
  }

  private static String defaultName(String type) {
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
      case TYPE_PHONE -> "Phone";
      case TYPE_INSURANCE -> "Insurance";
      case TYPE_CAR_INSURANCE -> "Car Insurance";
      case TYPE_TAXES -> "Taxes & Fees";
      case TYPE_CAR_MAINTENANCE -> "Car Maintenance";
      case TYPE_HOME -> "Home";
      case TYPE_GIFTS -> "Gifts & Donations";
      case TYPE_EDUCATION -> "Education";
      case TYPE_CHILDCARE -> "Childcare";
      case TYPE_SERVICES -> "Services";
      case TYPE_PETS -> "Pet Care";
      default -> "Other";
    };
  }

  /**
   * Load user's budget categories from S3.
   */
  /** the categories of their saved budget, as bank transactions are sorted into them */
  public Set<String> budgetCategories(String username) {
    return Set.copyOf(getUserCategories(username));
  }

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
    log.debug("Loaded {} categories for user {}: {}", categories.size(), username, categories);
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
