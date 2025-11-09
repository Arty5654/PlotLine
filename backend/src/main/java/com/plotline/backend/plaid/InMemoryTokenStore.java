package com.plotline.backend.plaid;

import org.springframework.stereotype.Component;
import java.util.*;

@Component
public class InMemoryTokenStore implements TokenStore {
  private final Map<String, Map<String, String>> byUser = new HashMap<>(); // user -> (itemId->token)
  private final Map<String, String> itemToUser = new HashMap<>();
  private final Map<String, Map<String, List<String>>> selectedByUser = new HashMap<>(); // user -> (itemId->accountIds)

  @Override
  public synchronized void saveAccessToken(String username, String itemId, String accessToken) {
    byUser.computeIfAbsent(username, k -> new HashMap<>()).put(itemId, accessToken);
    itemToUser.put(itemId, username);
  }

  @Override
  public synchronized String getAccessToken(String username) {
    var map = byUser.get(username);
    if (map == null || map.isEmpty()) return null;
    return map.values().iterator().next();
  }

  @Override
  public synchronized String getAccessToken(String username, String itemId) {
    var map = byUser.get(username);
    return map == null ? null : map.get(itemId);
  }

  @Override
  public synchronized Map<String, String> listAccessTokens(String username) {
    return byUser.getOrDefault(username, Map.of());
  }

  @Override
  public synchronized String usernameForItem(String itemId) {
    return itemToUser.get(itemId);
  }

  @Override
  public synchronized void saveSelectedAccounts(String username, String itemId, List<String> accountIds) {
    selectedByUser
        .computeIfAbsent(username, u -> new HashMap<>())
        .put(itemId, new ArrayList<>(accountIds));
  }

  @Override
  public synchronized List<String> getSelectedAccounts(String username, String itemId) {
    var perUser = selectedByUser.get(username);
    if (perUser == null) return List.of();
    return perUser.getOrDefault(itemId, List.of());
  }
}
