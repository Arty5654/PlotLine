package com.plotline.backend.plaid;

import java.util.*;

/**
 * In-memory cursor store - replaced by S3PlaidCursorStore for production.
 * Kept for reference/testing only.
 */
// @Component  // Disabled - using S3PlaidCursorStore instead
public class InMemoryPlaidCursorStore implements PlaidCursorStore {
  private final Map<String, String> cursorByUserItem = new HashMap<>();
  private final Set<String> seen = new HashSet<>(); // key: user|item|txn

  private static String key(String u, String i){ return u + "|" + i; }
  private static String tkey(String u, String i, String t){ return u + "|" + i + "|" + t; }

  @Override
  public synchronized String getCursor(String username, String itemId) {
    return cursorByUserItem.get(key(username, itemId));
  }

  @Override
  public synchronized void saveCursor(String username, String itemId, String cursor) {
    cursorByUserItem.put(key(username, itemId), cursor);
  }

  @Override
  public synchronized boolean hasSeenTxn(String username, String itemId, String transactionId) {
    return seen.contains(tkey(username, itemId, transactionId));
  }

  @Override
  public synchronized void markSeenTxn(String username, String itemId, String transactionId) {
    seen.add(tkey(username, itemId, transactionId));
  }

  @Override
  public synchronized void clearSyncState(String username) {
    String prefix = username + "|";
    cursorByUserItem.entrySet().removeIf(e -> e.getKey().startsWith(prefix));
    seen.removeIf(k -> k.startsWith(prefix));
  }
}
