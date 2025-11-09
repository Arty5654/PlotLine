package com.plotline.backend.categorize;

import org.springframework.stereotype.Component;
import java.util.*;

@Component
public class InMemoryUserCategoryStore implements UserCategoryStore {
  private final Map<String, Map<String,String>> byUser = new HashMap<>();

  @Override
  public synchronized String lookup(String username, String merchantNormalized) {
    var m = byUser.get(username);
    return m == null ? null : m.get(merchantNormalized);
  }

  @Override
  public synchronized void saveOverride(String username, String merchantNormalized, String category) {
    byUser.computeIfAbsent(username, k -> new HashMap<>())
          .put(merchantNormalized, category);
  }
}
