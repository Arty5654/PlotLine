package com.plotline.backend.plaid;

public interface PlaidCursorStore {
  String getCursor(String username, String itemId);
  void saveCursor(String username, String itemId, String cursor);
  boolean hasSeenTxn(String username, String itemId, String transactionId);
  void markSeenTxn(String username, String itemId, String transactionId);
}
