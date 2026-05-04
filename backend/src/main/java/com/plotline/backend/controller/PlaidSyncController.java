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


import java.time.LocalDate;
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

    System.out.println("=== Starting Plaid sync for user: " + username + " ===");

    // Clear cached categories so we get fresh user categories
    categorizer.clearCategoryCache(username);

    Map<String, String> tokens = tokenStore.listAccessTokens(username);
    if (tokens.isEmpty()) {
      System.out.println("No linked items for user: " + username);
      return ResponseEntity.badRequest().body(Map.of("error", "no linked items"));
    }

    int totalAdded = 0, totalModified = 0, totalRemoved = 0, daysUpdated = 0;
    int skippedPending = 0, skippedSeen = 0, skippedOld = 0, skippedNegative = 0;
    List<Map<String,Object>> uncategorized = new ArrayList<>();

    // Aggregate costs across ALL items (bank links) before writing
    Map<String, Map<String, Double>> dayMap = new LinkedHashMap<>();

    for (Map.Entry<String, String> entry : tokens.entrySet()) {
      final String itemId = entry.getKey();
      final String accessToken = entry.getValue();

      System.out.println("Processing item: " + itemId);

      // decide which account IDs we care about
      List<String> targetAccountIds =
          (accountIdsFilter != null && !accountIdsFilter.isEmpty())
              ? accountIdsFilter
              : tokenStore.getSelectedAccounts(username, itemId);

      // Always use cursor-based incremental sync.
      // Plaid's transactionsSync cursor tracks the item, not individual accounts,
      // so we filter accounts client-side after fetching.
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
        opts.setIncludePersonalFinanceCategory(Boolean.TRUE);
        req.setOptions(opts);

        TransactionsSyncResponse res = plaid.transactionsSync(req).execute().body();
        if (res == null) break;

        added.addAll(res.getAdded());
        modified.addAll(res.getModified());
        removed.addAll(res.getRemoved());

        cursor = res.getNextCursor();
        hasMore = Boolean.TRUE.equals(res.getHasMore());
      }

      System.out.println("Fetched from Plaid - added: " + added.size() +
          ", modified: " + modified.size() + ", removed: " + removed.size());

      // Always save cursor for incremental sync
      cursorStore.saveCursor(username, itemId, cursor);
      System.out.println("Saved cursor for item: " + itemId);

      // If caller selected accounts, filter results here
      if (targetAccountIds != null && !targetAccountIds.isEmpty()) {
        int beforeAdded = added.size();
        int beforeModified = modified.size();
        added.removeIf(t -> !targetAccountIds.contains(t.getAccountId()));
        modified.removeIf(t -> !targetAccountIds.contains(t.getAccountId()));
        removed.removeIf(t -> !targetAccountIds.contains(t.getAccountId()));
        System.out.println("After account filter - added: " + added.size() +
            " (was " + beforeAdded + "), modified: " + modified.size() + " (was " + beforeModified + ")");
      }

      // Only sync transactions from the last 30 days
      LocalDate cutoffDate = LocalDate.now().minusDays(30);

      // Process ADDED transactions
      for (Transaction t : added) {
        String txnName = t.getMerchantName() != null ? t.getMerchantName() : t.getName();
        double amount = t.getAmount().doubleValue();
        String plaidCat = t.getPersonalFinanceCategory() != null ?
            t.getPersonalFinanceCategory().getDetailed() : "none";

        if (Boolean.TRUE.equals(t.getPending())) {
          skippedPending++;
          continue;
        }
        if (cursorStore.hasSeenTxn(username, itemId, t.getTransactionId())) {
          skippedSeen++;
          continue;
        }
        if (t.getDate().isBefore(cutoffDate)) {
          skippedOld++;
          continue;
        }
        if (amount <= 0.0) {
          cursorStore.markSeenTxn(username, itemId, t.getTransactionId());
          skippedNegative++;
          continue;
        }

        System.out.println("Processing txn: " + txnName + " | $" + amount +
            " | date: " + t.getDate() + " | plaidCat: " + plaidCat);

        String bucket = categorizer.map(username, t);
        System.out.println("  → Categorized as: " + bucket);

        if (bucket == null || bucket.isBlank() || "UNCATEGORIZED".equalsIgnoreCase(bucket)) {
          uncategorized.add(Map.of(
              "id", t.getTransactionId(),
              "date", t.getDate().toString(),
              "name", t.getName(),
              "amount", amount,
              "accountId", t.getAccountId(),
              "plaidCategory", plaidCat != null ? plaidCat : ""
          ));
        } else {
          String date = t.getDate().toString();
          Map<String, Double> cats = dayMap.computeIfAbsent(date, k -> new LinkedHashMap<>());
          cats.put(bucket, round2(cats.getOrDefault(bucket, 0.0) + amount));
          // Store individual transaction detail
          costsWriter.storeTransaction(username, date, t.getTransactionId(), txnName, amount, bucket, "plaid");
          cursorStore.markSeenTxn(username, itemId, t.getTransactionId());
          totalAdded++;
        }
      }

      // Process MODIFIED transactions (use same categorizer.map)
      for (Transaction t : modified) {
        String txnName = t.getMerchantName() != null ? t.getMerchantName() : t.getName();
        double amount = t.getAmount().doubleValue();

        if (Boolean.TRUE.equals(t.getPending())) {
          skippedPending++;
          continue;
        }
        if (t.getDate().isBefore(cutoffDate)) {
          skippedOld++;
          continue;
        }
        if (amount <= 0.0) {
          skippedNegative++;
          continue;
        }

        // Use the same categorizer.map for modified transactions (not bucketFromPlaidOrFallback)
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
          // Store individual transaction detail
          costsWriter.storeTransaction(username, date, t.getTransactionId(), txnName, amount, bucket, "plaid");
          totalModified++;
        }
      }

      totalRemoved += removed.size();
    }

    // Write aggregated costs to storage (after processing ALL items)
    for (var e : dayMap.entrySet()) {
      if (e.getValue().isEmpty()) continue;
      String dayIso = e.getKey();
      Map<String, Double> costs = e.getValue();
      System.out.println("Writing costs for " + dayIso + ": " + costs);
      costsWriter.mergeDated(username, "weekly",  dayIso, costs);
      costsWriter.mergeDated(username, "monthly", dayIso, costs);
      daysUpdated++;
    }

    System.out.println("=== Sync complete for " + username + " ===");
    System.out.println("Added: " + totalAdded + ", Modified: " + totalModified +
        ", Removed: " + totalRemoved + ", Days updated: " + daysUpdated);
    System.out.println("Skipped - pending: " + skippedPending + ", seen: " + skippedSeen +
        ", old: " + skippedOld + ", negative: " + skippedNegative);
    System.out.println("Uncategorized: " + uncategorized.size());

    return ResponseEntity.ok(Map.of(
        "added", totalAdded,
        "modified", totalModified,
        "removed", totalRemoved,
        "daysUpdated", daysUpdated,
        "uncategorized", uncategorized
    ));
  } catch (Exception e) {
    System.err.println("Sync error for user: " + body.get("username"));
    System.err.println("Error type: " + e.getClass().getName());
    System.err.println("Error message: " + e.getMessage());
    e.printStackTrace();
    String errorMsg = e.getMessage() != null ? e.getMessage() : "Unknown error during sync";
    return ResponseEntity.status(500).body(Map.of("error", errorMsg));
  }
}



  /**
   * Skip (ignore) transactions - marks them as seen without adding to costs.
   * Use this when user doesn't want to categorize certain transactions.
   */
  @PostMapping("/skip-transactions")
  public ResponseEntity<?> skipTransactions(@RequestBody Map<String, Object> body) {
    try {
      String username = (String) body.get("username");
      @SuppressWarnings("unchecked")
      List<String> transactionIds = (List<String>) body.get("transaction_ids");

      if (username == null || transactionIds == null || transactionIds.isEmpty()) {
        return ResponseEntity.badRequest().body(Map.of("error", "Missing username or transaction_ids"));
      }

      // Get all items for this user to mark transactions as seen
      Map<String, String> tokens = tokenStore.listAccessTokens(username);
      int skipped = 0;

      for (String txnId : transactionIds) {
        // Mark as seen in all items (we don't know which item the txn belongs to)
        for (String itemId : tokens.keySet()) {
          cursorStore.markSeenTxn(username, itemId, txnId);
        }
        skipped++;
      }

      System.out.println("Skipped " + skipped + " transactions for user: " + username);
      return ResponseEntity.ok(Map.of("skipped", skipped));
    } catch (Exception e) {
      System.err.println("Error skipping transactions: " + e.getMessage());
      return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
    }
  }

  /**
   * Reset sync state - clears cursors and seen transactions.
   * This allows a full re-sync of all transactions from Plaid.
   * Use this when transactions seem to be missing or you want to start fresh.
   */
  @PostMapping("/reset-sync")
  public ResponseEntity<?> resetSync(@RequestBody Map<String, Object> body) {
    try {
      String username = (String) body.get("username");

      if (username == null || username.isBlank()) {
        return ResponseEntity.badRequest().body(Map.of("error", "Missing username"));
      }

      System.out.println("=== Resetting sync state for user: " + username + " ===");

      // Clear all cursor and seen transaction state
      cursorStore.clearSyncState(username);

      // Also clear the categorizer cache
      categorizer.clearCategoryCache(username);

      System.out.println("Sync state reset complete for: " + username);
      return ResponseEntity.ok(Map.of(
          "success", true,
          "message", "Sync state cleared. Next sync will fetch all transactions from the last 30 days."
      ));
    } catch (Exception e) {
      System.err.println("Error resetting sync state: " + e.getMessage());
      e.printStackTrace();
      return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
    }
  }

  private static double round2(double v) { return Math.round(v * 100.0) / 100.0; }
}
