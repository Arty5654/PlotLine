package com.plotline.backend.categorize;

import com.plaid.client.model.Transaction;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@Component
public class Categorizer {
  private final UserCategoryStore userStore;

  public Categorizer(UserCategoryStore store) { this.userStore = store; }

  private static final Map<String,String> PFC_PRIMARY_TO_BUCKET = Map.ofEntries(
      Map.entry("FOOD_AND_DRINK", "Eating Out"),
      Map.entry("GROCERIES", "Groceries"),
      Map.entry("TRANSPORTATION", "Transportation"),
      Map.entry("RENT_AND_UTILITIES", "Utilities"),
      Map.entry("SUBSCRIPTIONS", "Subscriptions"),
      Map.entry("ENTERTAINMENT", "Entertainment")
  );

  private static final Map<String,String> MERCHANT_RULES = Map.ofEntries(
      Map.entry("STARBUCKS", "Eating Out"),
      Map.entry("MCDONALD'S", "Eating Out"),
      Map.entry("UBER", "Transportation"),
      Map.entry("LYFT", "Transportation"),
      Map.entry("SPOTIFY", "Subscriptions"),
      Map.entry("NETFLIX", "Subscriptions"),
      Map.entry("WHOLE FOODS", "Groceries"),
      Map.entry("TRADER JOE'S", "Groceries"),
      Map.entry("SAFEWAY", "Groceries")
  );

  public String map(String username, Transaction t) {
    String merchant = (t.getMerchantName() != null ? t.getMerchantName() : t.getName());
    String m = merchant == null ? "" : merchant.toUpperCase().trim();

    String userOverride = userStore.lookup(username, m);
    if (userOverride != null) return userOverride;

    if (t.getPersonalFinanceCategory() != null && t.getPersonalFinanceCategory().getPrimary() != null) {
      String p = t.getPersonalFinanceCategory().getPrimary();
      if (PFC_PRIMARY_TO_BUCKET.containsKey(p)) return PFC_PRIMARY_TO_BUCKET.get(p);
    }

    for (var e : MERCHANT_RULES.entrySet()) {
      if (m.contains(e.getKey())) return e.getValue();
    }
    return "Uncategorized";
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
