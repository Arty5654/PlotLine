package com.plotline.backend.plaid;

import java.util.List;
import java.util.Map;

public interface TokenStore {
  void saveAccessToken(String username, String itemId, String accessToken);
  String getAccessToken(String username); // optional convenience (first/only item)
  String getAccessToken(String username, String itemId);
  java.util.Map<String,String> listAccessTokens(String username); // itemId -> token
  String usernameForItem(String itemId);

  void saveSelectedAccounts(String username, String itemId, List<String> accountIds);
  List<String> getSelectedAccounts(String username, String itemId);
}