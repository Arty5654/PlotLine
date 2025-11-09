package com.plotline.backend.controller;

import com.plaid.client.request.PlaidApi;
import com.plaid.client.model.*;
import com.plaid.client.model.TransactionsSyncRequestOptions;
import com.plotline.backend.categorize.Categorizer;
import com.plotline.backend.costs.CostsWriter;
import com.plotline.backend.plaid.PlaidCursorStore;
import com.plotline.backend.plaid.TokenStore;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;


import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/plaid")
public class PlaidSyncController {
  private final PlaidApi plaid;
  private final TokenStore tokenStore;
  private final PlaidCursorStore cursorStore;
  private final Categorizer categorizer;
  private final CostsWriter costsWriter;

  public PlaidSyncController(
      PlaidApi plaid,
      TokenStore tokenStore,
      PlaidCursorStore cursorStore,
      Categorizer categorizer,
      CostsWriter costsWriter
  ) {
    this.plaid = plaid;
    this.tokenStore = tokenStore;
    this.cursorStore = cursorStore;
    this.categorizer = categorizer;
    this.costsWriter = costsWriter;
  }

@PostMapping("/sync")
public ResponseEntity<?> sync(@RequestBody Map<String, Object> body) {
  try {
    String username = (String) body.get("username");
    @SuppressWarnings("unchecked")
    List<String> accountIdsFilter = (List<String>) body.get("account_ids");

    Map<String, String> tokens = tokenStore.listAccessTokens(username);
    if (tokens.isEmpty()) {
      return ResponseEntity.badRequest().body(Map.of("error", "no linked items"));
    }

    int totalAdded = 0, totalModified = 0, totalRemoved = 0, daysUpdated = 0;
    List<Map<String,Object>> uncategorized = new ArrayList<>();

    for (Map.Entry<String, String> entry : tokens.entrySet()) {
      final String itemId = entry.getKey();
      final String accessToken = entry.getValue();

      // decide which account IDs we care about
      List<String> targetAccountIds =
          (accountIdsFilter != null && !accountIdsFilter.isEmpty())
              ? accountIdsFilter
              : tokenStore.getSelectedAccounts(username, itemId);

      String cursor = cursorStore.getCursor(username, itemId);
      boolean hasMore = true;

      List<Transaction> added = new ArrayList<>();
      List<Transaction> modified = new ArrayList<>();
      List<RemovedTransaction> removed = new ArrayList<>();

      while (hasMore) {
        TransactionsSyncRequest req = new TransactionsSyncRequest()
            .accessToken(accessToken)
            .cursor(cursor);
        // NOTE: no accountId/accountIds on the request – filter client-side below

        // Ask Plaid to include Personal Finance Categories in the response
        TransactionsSyncRequestOptions opts = new TransactionsSyncRequestOptions();
        opts.setIncludePersonalFinanceCategory(Boolean.TRUE);  // or opts.includePersonalFinanceCategory(true) on some versions
        req.setOptions(opts);

        TransactionsSyncResponse res = plaid.transactionsSync(req).execute().body();
        if (res == null) break;

        added.addAll(res.getAdded());
        modified.addAll(res.getModified());
        removed.addAll(res.getRemoved());

        cursor = res.getNextCursor();
        hasMore = Boolean.TRUE.equals(res.getHasMore());
      }

      // Save per-item cursor here (it's in scope)
      cursorStore.saveCursor(username, itemId, cursor);

      // If caller selected accounts, filter results here
      if (targetAccountIds != null && !targetAccountIds.isEmpty()) {
        added.removeIf(t -> !targetAccountIds.contains(t.getAccountId()));
        modified.removeIf(t -> !targetAccountIds.contains(t.getAccountId()));
        removed.removeIf(t -> !targetAccountIds.contains(t.getAccountId()));
      }

      // Aggregate only categorized; collect uncategorized to return to client
      Map<String, Map<String, Double>> dayMap = new LinkedHashMap<>();

      for (Transaction t : added) {
        if (Boolean.TRUE.equals(t.getPending())) continue;
        if (cursorStore.hasSeenTxn(username, itemId, t.getTransactionId())) continue;
        double amount = t.getAmount().doubleValue();
        if (amount == 0.0) continue;

        String bucket = categorizer.map(username, t);
        if (bucket == null || bucket.isBlank() || "UNCATEGORIZED".equalsIgnoreCase(bucket)) {
          uncategorized.add(Map.of(
              "id", t.getTransactionId(),
              "date", t.getDate().toString(),
              "name", t.getName(),
              "amount", amount,
              "accountId", t.getAccountId()
          ));
        } else {
          String date = t.getDate().toString();
          Map<String, Double> cats = dayMap.computeIfAbsent(date, k -> new LinkedHashMap<>());
          cats.put(bucket, round2(cats.getOrDefault(bucket, 0.0) + amount));
          cursorStore.markSeenTxn(username, itemId, t.getTransactionId());
          totalAdded++;
        }
      }

      for (Transaction t : modified) {
        if (Boolean.TRUE.equals(t.getPending())) continue;
        double amount = t.getAmount().doubleValue();
        if (amount == 0.0) continue;

        String bucket = bucketFromPlaidOrFallback(username, t);
        if (bucket == null || bucket.isBlank() || "UNCATEGORIZED".equalsIgnoreCase(bucket)) {
          uncategorized.add(Map.of(
              "id", t.getTransactionId(),
              "date", t.getDate().toString(),
              "name", t.getName(),
              "amount", amount,
              "accountId", t.getAccountId()
          ));
        } else {
          String date = t.getDate().toString();
          Map<String, Double> cats = dayMap.computeIfAbsent(date, k -> new LinkedHashMap<>());
          cats.put(bucket, round2(cats.getOrDefault(bucket, 0.0) + amount));
          totalModified++;
        }
      }

      for (var e : dayMap.entrySet()) {
        if (e.getValue().isEmpty()) continue;
        String dayIso = e.getKey();
        Map<String, Double> costs = e.getValue();
        costsWriter.mergeDated(username, "weekly",  dayIso, costs);
        costsWriter.mergeDated(username, "monthly", dayIso, costs);
        daysUpdated++;
      }

      totalRemoved += removed.size();
    }

    return ResponseEntity.ok(Map.of(
        "added", totalAdded,
        "modified", totalModified,
        "removed", totalRemoved,
        "daysUpdated", daysUpdated,
        "uncategorized", uncategorized
    ));
  } catch (Exception e) {
    e.printStackTrace();
    return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
  }
}



  private static double round2(double v) { return Math.round(v * 100.0) / 100.0; }

  private String bucketFromPlaidOrFallback(String username, Transaction t) {
    PersonalFinanceCategory pfc = t.getPersonalFinanceCategory();
    if (pfc != null) {
      String detailed = pfc.getDetailed();
      String primary  = pfc.getPrimary();
      if (detailed != null && !detailed.isBlank()) return detailed;  // e.g., "COFFEE_SHOP"
      if (primary  != null && !primary.isBlank())  return primary;   // e.g., "FOOD_AND_DRINK"
    }
    // Fallback to your existing heuristic
    return categorizer.map(username, t);
  }
}
