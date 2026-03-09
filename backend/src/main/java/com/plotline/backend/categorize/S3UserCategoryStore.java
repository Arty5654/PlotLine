package com.plotline.backend.categorize;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.service.S3Service;
import org.springframework.context.annotation.Primary;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * S3-backed UserCategoryStore that persists merchant → category overrides.
 * When a user manually categorizes a transaction, that mapping is saved
 * and will be used for future transactions from the same merchant.
 */
@Component
@Primary
public class S3UserCategoryStore implements UserCategoryStore {
    private static final String OVERRIDES_PREFIX = "plaid/category-overrides/";

    private final S3Service s3Service;
    private final ObjectMapper objectMapper = new ObjectMapper();

    // In-memory cache: username -> (merchantNormalized -> category)
    private final Map<String, Map<String, String>> cache = new ConcurrentHashMap<>();
    private final Set<String> loadedUsers = ConcurrentHashMap.newKeySet();

    public S3UserCategoryStore(S3Service s3Service) {
        this.s3Service = s3Service;
        System.out.println("S3UserCategoryStore initialized - merchant overrides will persist across restarts");
    }

    @Override
    public synchronized String lookup(String username, String merchantNormalized) {
        loadIfNeeded(username);
        Map<String, String> userOverrides = cache.get(username);
        if (userOverrides == null) {
            return null;
        }
        return userOverrides.get(merchantNormalized);
    }

    @Override
    public synchronized void saveOverride(String username, String merchantNormalized, String category) {
        loadIfNeeded(username);
        cache.computeIfAbsent(username, k -> new ConcurrentHashMap<>())
             .put(merchantNormalized, category);
        persistOverrides(username);
        System.out.println("Saved category override for " + username + ": " + merchantNormalized + " → " + category);
    }

    private void loadIfNeeded(String username) {
        if (loadedUsers.contains(username)) {
            return;
        }

        try {
            String s3Key = OVERRIDES_PREFIX + username.toLowerCase() + ".json";
            byte[] data = s3Service.downloadFile(s3Key);
            if (data != null) {
                Map<String, String> overrides = objectMapper.readValue(data,
                    new TypeReference<Map<String, String>>() {});
                cache.put(username, new ConcurrentHashMap<>(overrides));
                System.out.println("Loaded " + overrides.size() + " category overrides for user " + username);
            }
        } catch (Exception e) {
            // No overrides found or error - that's fine
        }
        loadedUsers.add(username);
    }

    private void persistOverrides(String username) {
        try {
            Map<String, String> userOverrides = cache.get(username);
            if (userOverrides == null || userOverrides.isEmpty()) {
                return;
            }

            String s3Key = OVERRIDES_PREFIX + username.toLowerCase() + ".json";
            String json = objectMapper.writeValueAsString(userOverrides);

            // Use the S3Service to upload
            java.io.ByteArrayInputStream inputStream = new java.io.ByteArrayInputStream(
                json.getBytes(StandardCharsets.UTF_8));
            s3Service.uploadFile(s3Key, inputStream, json.length());
        } catch (Exception e) {
            System.err.println("Error persisting category overrides for " + username + ": " + e.getMessage());
        }
    }
}
