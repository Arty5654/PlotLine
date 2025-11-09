package com.plotline.backend.categorize;

public interface UserCategoryStore {
  String lookup(String username, String merchantNormalized);
  void saveOverride(String username, String merchantNormalized, String category);
}