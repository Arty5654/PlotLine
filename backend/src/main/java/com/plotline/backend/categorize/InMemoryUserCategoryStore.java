package com.plotline.backend.categorize;

import java.util.*;

/**
 * In-memory category store - replaced by S3UserCategoryStore for production.
 * Kept for reference/testing only.
 */
// @Component  // Disabled - using S3UserCategoryStore instead
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
