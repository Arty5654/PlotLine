package com.plotline.backend.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

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
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/plaid")
public class PlaidSyncController {
    private static final Logger log = LoggerFactory.getLogger(PlaidSyncController.class);

  private final PlaidApi plaid;
  private final TokenStore tokenStore;
  private final PlaidCursorStore cursorStore;
  private final Categorizer categorizer;
  private final CostsWriter costsWriter;
  private final com.plotline.backend.service.FixedCosts fixedCosts;

  public PlaidSyncController(
      PlaidApi plaid,
      TokenStore tokenStore,
      PlaidCursorStore cursorStore,
      Categorizer categorizer,
      CostsWriter costsWriter,
      com.plotline.backend.service.FixedCosts fixedCosts
  ) {
    this.plaid = plaid;
    this.tokenStore = tokenStore;
    this.cursorStore = cursorStore;
    this.categorizer = categorizer;
    this.costsWriter = costsWriter;
    this.fixedCosts = fixedCosts;
  }

@PostMapping("/sync")
public ResponseEntity<?> sync(@RequestBody Map<String, Object> body) {
  try {
    String username = (String) body.get("username");
    @SuppressWarnings("unchecked")
    List<String> accountIdsFilter = (List<String>) body.get("account_ids");

    log.debug("=== Starting Plaid sync for user: {} ===", username);

    // Clear cached categories so we get fresh user categories
    categorizer.clearCategoryCache(username);

    Map<String, String> tokens = tokenStore.listAccessTokens(username);
    if (tokens.isEmpty()) {
      log.debug("No linked items for user: {}", username);
      return ResponseEntity.badRequest().body(Map.of("error", "no linked items"));
    }

    int totalAdded = 0, totalModified = 0, totalRemoved = 0, daysUpdated = 0;
    int skippedPending = 0, skippedSeen = 0, skippedOld = 0, skippedNegative = 0, skippedFixed = 0;
    // how far back: 30 days normally; the budget quiz brings in the 90 days it looked at
    int days = body.get("days") instanceof Number n ? Math.max(1, Math.min(90, n.intValue())) : 30;
    // categories that are fixed costs are counted from Monthly Costs, not from the bank (no double counting)
    java.util.Set<String> fixedCategories = fixedCosts.categories(com.plotline.backend.util.UsernameUtils.normalize(username));
    List<Map<String,Object>> uncategorized = new ArrayList<>();

    // Aggregate costs across ALL items (bank links) before writing
    Map<String, Map<String, Double>> dayMap = new LinkedHashMap<>();

    for (Map.Entry<String, String> entry : tokens.entrySet()) {
      final String itemId = entry.getKey();
      final String accessToken = entry.getValue();

      log.debug("Processing item: {}", itemId);

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

      log.debug("Fetched from Plaid - added: {}, modified: {}, removed: {}", added.size(), modified.size(), removed.size());

      // Always save cursor for incremental sync
      cursorStore.saveCursor(username, itemId, cursor);
      log.debug("Saved cursor for item: {}", itemId);

      // If caller selected accounts, filter results here
      if (targetAccountIds != null && !targetAccountIds.isEmpty()) {
        int beforeAdded = added.size();
        int beforeModified = modified.size();
        added.removeIf(t -> !targetAccountIds.contains(t.getAccountId()));
        modified.removeIf(t -> !targetAccountIds.contains(t.getAccountId()));
        // removed ones aren't filtered: only ones that were recorded are taken out
        log.debug("After account filter - added: {} (was {}), modified: {} (was {})", added.size(), beforeAdded, modified.size(), beforeModified);
      }

      // Only sync transactions from the last 30 days
      LocalDate cutoffDate = LocalDate.now().minusDays(days);

      // Process ADDED transactions
      // merchants the bank couldn't label: asked about once (AI), so they're sorted instead of Miscellaneous
      List<Transaction> toSort = new ArrayList<>(added);
      toSort.addAll(modified);
      if (!toSort.isEmpty()) categorizer.prepare(username, toSort);

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
        if (amount <= 0.0 && !SpendingSummaryController.isRefund(t)) {
          cursorStore.markSeenTxn(username, itemId, t.getTransactionId());
          skippedNegative++;
          continue;
        }

        log.debug("Processing txn: {} | ${} | date: {} | plaidCat: {}", txnName, amount, t.getDate(), plaidCat);

        String bucket = categorizer.map(username, t);
        log.debug(" → Categorized as: {}", bucket);
        if (bucket != null && countedAsFixed(fixedCategories, username, t, bucket)) {
          // a fixed cost (rent, a car payment...): already counted every month
          cursorStore.markSeenTxn(username, itemId, t.getTransactionId());
          skippedFixed++;
          continue;
        }

        boolean unsorted = bucket == null || bucket.isBlank() || "UNCATEGORIZED".equalsIgnoreCase(bucket);
        if (unsorted && amount < 0) {
          // a refund with nowhere to go back to: not asked about
          cursorStore.markSeenTxn(username, itemId, t.getTransactionId());
          skippedNegative++;
        } else if (unsorted) {
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
        // already counted (the bank renamed or re-labeled it): counting it again would double it
        if (cursorStore.hasSeenTxn(username, itemId, t.getTransactionId())) {
          skippedSeen++;
          continue;
        }
        if (t.getDate().isBefore(cutoffDate)) {
          skippedOld++;
          continue;
        }
        if (amount <= 0.0 && !SpendingSummaryController.isRefund(t)) {
          skippedNegative++;
          continue;
        }

        // Use the same categorizer.map for modified transactions (not bucketFromPlaidOrFallback)
        String bucket = categorizer.map(username, t);
        if (bucket != null && countedAsFixed(fixedCategories, username, t, bucket)) {
          cursorStore.markSeenTxn(username, itemId, t.getTransactionId());
          skippedFixed++;
          continue;
        }

        boolean unsorted = bucket == null || bucket.isBlank() || "UNCATEGORIZED".equalsIgnoreCase(bucket);
        if (unsorted && amount < 0) {
          skippedNegative++;
        } else if (unsorted) {
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
          cursorStore.markSeenTxn(username, itemId, t.getTransactionId());
          totalModified++;
        }
      }

      // charges the bank took back: out of Monthly Costs (pending ones were never counted, so nothing to undo)
      for (RemovedTransaction r : removed) {
        if (r.getTransactionId() != null && costsWriter.removeTransaction(username, r.getTransactionId())) totalRemoved++;
      }
    }

    // Write aggregated costs to storage (after processing ALL items)
    for (var e : dayMap.entrySet()) {
      if (e.getValue().isEmpty()) continue;
      String dayIso = e.getKey();
      Map<String, Double> costs = e.getValue();
      log.debug("Writing costs for {}: {}", dayIso, costs);
      // added to what the day already has (earlier syncs, amounts typed in), never replacing it
      costsWriter.addDated(username, "weekly",  dayIso, costs);
      costsWriter.addDated(username, "monthly", dayIso, costs);
      daysUpdated++;
    }

    log.debug("=== Sync complete for {} ===", username);
    log.debug("Added: {}, Modified: {}, Removed: {}, Days updated: {}", totalAdded, totalModified, totalRemoved, daysUpdated);
    log.debug("Skipped - pending: {}, seen: {}, old: {}, negative: {}, fixed costs: {}", skippedPending, skippedSeen, skippedOld, skippedNegative, skippedFixed);
    log.debug("Uncategorized: {}", uncategorized.size());

    // refunds an older version marked handled without recording (once per person)
    int caughtUp = catchUpRefunds(username);
    totalAdded += caughtUp;
    log.info("Sync: {} added, {} updated, {} taken out (reversed), {} fixed costs left out, {} to assign",
        totalAdded, totalModified, totalRemoved, skippedFixed, uncategorized.size());

    return ResponseEntity.ok(Map.of(
        "added", totalAdded,
        "modified", totalModified,
        "removed", totalRemoved,
        "daysUpdated", daysUpdated,
        "skippedFixed", skippedFixed,
        "uncategorized", uncategorized
    ));
  } catch (Exception e) {
    log.error("Sync error for user: {}", body.get("username"));
    log.error("Error type: {}", e.getClass().getName());
    log.error("Error message: {}", e.getMessage());
    log.error("sync failed", e);
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

      log.debug("Skipped {} transactions for user: {}", skipped, username);
      return ResponseEntity.ok(Map.of("skipped", skipped));
    } catch (Exception e) {
      log.error("Error skipping transactions: {}", e.getMessage());
      return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
    }
  }

  /**
   * Reset sync state - clears cursors and seen transactions.
   * This allows a full re-sync of all transactions from Plaid.
   * Use this when transactions seem to be missing or you want to start fresh.
   */
  /**
   * After the budget quiz is saved: the last 90 days of transactions (the same ones the quiz read),
   * fetched by date rather than from where sync left off, so earlier syncs don't cut it short.
   * Already-recorded transactions are skipped (and later syncs skip these), fixed-cost categories
   * aren't added (counted every month already), and what can't be sorted goes to Miscellaneous like
   * on the quiz, instead of dozens of "assign a category" prompts.
   * Body: {username, days (max 90)}
   */
  @PostMapping("/import-history")
  public ResponseEntity<?> importHistory(@RequestBody Map<String, Object> body) {
    try {
      String username = (String) body.get("username");
      if (username == null || username.isBlank()) return ResponseEntity.badRequest().body(Map.of("error", "Missing username"));
      int days = body.get("days") instanceof Number n ? Math.max(1, Math.min(90, n.intValue())) : 90;
      categorizer.clearCategoryCache(username);
      if (tokenStore.listAccessTokens(username).isEmpty()) return ResponseEntity.badRequest().body(Map.of("error", "no linked items"));
      int caughtUp = catchUpRefunds(username);
      // the quiz's edits: transaction id -> the category they moved it to, or "" for removed
      Map<String, String> edits = new HashMap<>();
      if (body.get("edits") instanceof Map<?, ?> e) e.forEach((k, v) -> { if (k != null && v instanceof String c) edits.put(String.valueOf(k), c.strip()); });
      Map<String, Integer> counts = importDays(username, days, false, edits);
      counts.merge("added", caughtUp, Integer::sum);
      return ResponseEntity.ok(counts);
    } catch (Exception e) {
      log.error("import-history failed", e);
      return ResponseEntity.status(500).body(Map.of("error", "Couldn't bring in your transactions."));
    }
  }

  /**
   * Once per person: refunds synced before refunds counted (Oct 16, 2026) were marked handled without
   * being recorded, so neither sync nor the import would ever bring them in. This brings in the last
   * 90 days of refunds that aren't in Monthly Costs, whatever they were marked. Reset Sync runs it again.
   */
  private int catchUpRefunds(String username) {
    if (cursorStore.hasSeenTxn(username, REFUND_CATCH_UP, REFUND_CATCH_UP)) return 0;
    try {
      int added = importDays(username, 90, true, Map.of()).getOrDefault("added", 0);
      cursorStore.markSeenTxn(username, REFUND_CATCH_UP, REFUND_CATCH_UP);
      if (added > 0) log.info("Refund catch-up: {} refund(s) brought in", added);
      return added;
    } catch (Exception e) {
      log.warn("Refund catch-up failed: {}", e.getMessage());
      return 0;
    }
  }

  private static final String REFUND_CATCH_UP = "refund-catch-up-2026-10";

  /**
   * The last `days` days by date, picked accounts only: what isn't recorded yet goes into Monthly Costs
   * (unsortable spending into Miscellaneous; fixed costs' left out). refundsOnly: just refunds, and
   * "recorded" means in Monthly Costs, not marked handled (the catch-up). edits: the quiz's removes ("")
   * and moves (a category) by transaction id, applied to ones already recorded too.
   */
  private Map<String, Integer> importDays(String username, int days, boolean refundsOnly, Map<String, String> edits) throws Exception {
    Map<String, String> tokens = tokenStore.listAccessTokens(username);
    java.util.Set<String> fixedCategories = fixedCosts.categories(com.plotline.backend.util.UsernameUtils.normalize(username));
    LocalDate end = LocalDate.now(), start = end.minusDays(days);
    Map<String, Map<String, Double>> dayMap = new LinkedHashMap<>();
    Map<String, java.util.Set<String>> recorded = new HashMap<>(); // month -> ids already in Monthly Costs
    int added = 0, skippedSeen = 0, skippedFixed = 0, edited = 0;
    for (var entry : tokens.entrySet()) {
      String itemId = entry.getKey();
      List<String> selected = tokenStore.getSelectedAccounts(username, itemId);
      List<Transaction> spending = new ArrayList<>();
      int offset = 0;
      while (true) {
        var response = plaid.transactionsGet(new TransactionsGetRequest().accessToken(entry.getValue()).startDate(start).endDate(end)
            .options(new TransactionsGetRequestOptions().count(500).offset(offset).includePersonalFinanceCategory(true))).execute();
        TransactionsGetResponse page = response.body();
        if (!response.isSuccessful() || page == null) break; // still loading (PRODUCT_NOT_READY): sync later picks it up
        for (Transaction t : page.getTransactions()) {
          if (selected != null && !selected.isEmpty() && !selected.contains(t.getAccountId())) continue;
          if (SpendingSummaryController.isRefund(t)) { spending.add(t); continue; } // money back lowers its category
          if (refundsOnly) continue;
          if (Boolean.TRUE.equals(t.getPending()) || t.getAmount() == null || t.getAmount() <= 0) continue;
          String primary = t.getPersonalFinanceCategory() != null ? t.getPersonalFinanceCategory().getPrimary() : null;
          if (primary != null && SpendingSummaryController.NOT_SPENDING.contains(primary)) continue; // transfers, card/loan payments, income
          spending.add(t);
        }
        offset += page.getTransactions().size();
        if (page.getTransactions().isEmpty() || offset >= page.getTotalTransactions()) break;
      }
      if (!spending.isEmpty()) categorizer.prepare(username, spending);
      for (Transaction t : spending) {
        // already counted: by a sync, or handed out by one for assigning and assigned by hand
        String month = t.getDate().toString().substring(0, 7);
        boolean stored = recorded.computeIfAbsent(month, m -> costsWriter.storedTransactionIds(username, m)).contains(t.getTransactionId());
        String edit = edits.get(t.getTransactionId());
        if (edit != null) {
          // removed in the quiz: not counted (taken out if it's there); moved: in that category
          cursorStore.markSeenTxn(username, itemId, t.getTransactionId());
          if (edit.isEmpty() || fixedCategories.contains(edit.toLowerCase())) {
            if (stored) { costsWriter.deleteTransaction(username, month, t.getTransactionId()); edited++; }
            else skippedFixed += edit.isEmpty() ? 0 : 1;
            continue;
          }
          if (stored) {
            costsWriter.moveTransaction(username, month, t.getTransactionId(), edit);
            edited++;
            continue;
          }
          String date = t.getDate().toString();
          Map<String, Double> cats = dayMap.computeIfAbsent(date, k -> new LinkedHashMap<>());
          cats.put(edit, round2(cats.getOrDefault(edit, 0.0) + t.getAmount()));
          String name = t.getMerchantName() != null ? t.getMerchantName() : t.getName();
          // what they chose here stays put when the budget's categories change later
          costsWriter.storeTransactionChosen(username, date, t.getTransactionId(), name, t.getAmount(), edit);
          added++;
          continue;
        }
        if (stored || (!refundsOnly && cursorStore.hasSeenTxn(username, itemId, t.getTransactionId()))) {
          skippedSeen++;
          continue;
        }
        String bucket = categorizer.map(username, t);
        cursorStore.markSeenTxn(username, itemId, t.getTransactionId());
        if (bucket == null || bucket.isBlank() || "UNCATEGORIZED".equalsIgnoreCase(bucket)) {
          if (t.getAmount() < 0) continue; // a refund with nowhere to go back to
          bucket = "Miscellaneous";
        }
        if (countedAsFixed(fixedCategories, username, t, bucket)) { skippedFixed++; continue; }
        String date = t.getDate().toString();
        Map<String, Double> cats = dayMap.computeIfAbsent(date, k -> new LinkedHashMap<>());
        cats.put(bucket, round2(cats.getOrDefault(bucket, 0.0) + t.getAmount()));
        String name = t.getMerchantName() != null ? t.getMerchantName() : t.getName();
        costsWriter.storeTransaction(username, date, t.getTransactionId(), name, t.getAmount(), bucket, "plaid");
        added++;
      }
    }
    for (var e : dayMap.entrySet()) {
      costsWriter.addDated(username, "weekly", e.getKey(), e.getValue());
      costsWriter.addDated(username, "monthly", e.getKey(), e.getValue());
    }
    Map<String, Integer> counts = new LinkedHashMap<>();
    counts.put("added", added);
    counts.put("skippedSeen", skippedSeen);
    counts.put("skippedFixed", skippedFixed);
    counts.put("daysUpdated", dayMap.size());
    counts.put("edited", edited);
    return counts;
  }

  /**
   * Counted by a fixed cost already: its category is one (rent, a car payment), or the broad one it
   * belongs to is (a Netflix charge with Subscriptions fixed, even if they have Streaming Services).
   */
  private boolean countedAsFixed(java.util.Set<String> fixed, String username, Transaction t, String bucket) {
    if (fixed.isEmpty()) return false;
    if (fixed.contains(bucket.toLowerCase())) return true;
    String broad = categorizer.mapBroad(username, t);
    return broad != null && fixed.contains(broad.toLowerCase());
  }

  @PostMapping("/reset-sync")
  public ResponseEntity<?> resetSync(@RequestBody Map<String, Object> body) {
    try {
      String username = (String) body.get("username");

      if (username == null || username.isBlank()) {
        return ResponseEntity.badRequest().body(Map.of("error", "Missing username"));
      }

      log.debug("=== Resetting sync state for user: {} ===", username);

      // Clear all cursor and seen transaction state
      cursorStore.clearSyncState(username);

      // Also clear the categorizer cache
      categorizer.clearCategoryCache(username);

      log.debug("Sync state reset complete for: {}", username);
      return ResponseEntity.ok(Map.of(
          "success", true,
          "message", "Sync state cleared. Next sync will fetch all transactions from the last 30 days."
      ));
    } catch (Exception e) {
      log.error("Error resetting sync state: {}", e.getMessage());
      log.error("resetSync failed", e);
      return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
    }
  }

  private static double round2(double v) { return Math.round(v * 100.0) / 100.0; }
}
