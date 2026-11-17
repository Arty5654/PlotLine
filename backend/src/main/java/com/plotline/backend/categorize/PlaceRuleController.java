package com.plotline.backend.categorize;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.plotline.backend.costs.TransactionResorter;

/**
 * "Always put this place in…": every transaction from a place goes to the category they pick, from
 * now on (sync, the quiz, re-sorting) and for the last 90 days in Monthly Costs.
 * Body: {username, merchant (the name as shown), category}
 */
@RestController
public class PlaceRuleController {

    private final UserCategoryStore rules;
    private final TransactionResorter resorter;
    private final Categorizer categorizer;

    public PlaceRuleController(UserCategoryStore rules, TransactionResorter resorter, Categorizer categorizer) {
        this.rules = rules;
        this.resorter = resorter;
        this.categorizer = categorizer;
    }

    @PostMapping("/api/category/place")
    public ResponseEntity<?> always(@RequestBody Map<String, Object> body) {
        String username = body.get("username") instanceof String u ? u.strip() : "";
        String merchant = body.get("merchant") instanceof String m ? m.strip().toUpperCase() : "";
        String category = body.get("category") instanceof String c ? c.strip() : "";
        if (username.isEmpty() || merchant.isEmpty() || category.isEmpty() || category.length() > 60 || merchant.length() > 200) {
            return ResponseEntity.badRequest().body(Map.of("error", "Expected {username, merchant, category}"));
        }
        rules.saveOverride(username, merchant, category);
        categorizer.clearCategoryCache(username);
        return ResponseEntity.ok(Map.of("moved", resorter.applyPlaceRule(username, merchant, category)));
    }
}
