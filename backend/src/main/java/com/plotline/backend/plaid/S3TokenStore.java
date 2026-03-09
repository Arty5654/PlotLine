package com.plotline.backend.plaid;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.cdimascio.dotenv.Dotenv;
import org.springframework.context.annotation.Primary;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * S3-backed TokenStore that persists Plaid access tokens.
 * Tokens survive backend restarts/redeployments.
 */
@Component
@Primary
public class S3TokenStore implements TokenStore {
    private static final String BUCKET_NAME = "plotline-database-bucket";
    private static final String TOKENS_PREFIX = "plaid/tokens/";
    private static final String ACCOUNTS_PREFIX = "plaid/selected-accounts/";

    private final S3Client s3Client;
    private final ObjectMapper objectMapper = new ObjectMapper();

    // In-memory cache to reduce S3 reads
    private final Map<String, Map<String, String>> tokenCache = new ConcurrentHashMap<>();
    private final Map<String, String> itemToUserCache = new ConcurrentHashMap<>();
    private final Map<String, Map<String, List<String>>> selectedAccountsCache = new ConcurrentHashMap<>();

    public S3TokenStore() {
        Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();

        String accessKey = System.getenv("AWS_ACCESS_KEY_ID");
        String secretKey = System.getenv("AWS_SECRET_ACCESS_KEY");
        String region = System.getenv("AWS_REGION");

        // Fall back to dotenv for local dev
        if (accessKey == null || accessKey.isBlank()) accessKey = dotenv.get("AWS_ACCESS_KEY_ID");
        if (secretKey == null || secretKey.isBlank()) secretKey = dotenv.get("AWS_SECRET_ACCESS_KEY");
        if (region == null || region.isBlank()) region = dotenv.get("AWS_REGION");

        this.s3Client = S3Client.builder()
            .region(Region.of(region))
            .credentialsProvider(StaticCredentialsProvider.create(
                AwsBasicCredentials.create(accessKey, secretKey)))
            .build();

        System.out.println("S3TokenStore initialized - tokens will persist across restarts");
    }

    @Override
    public synchronized void saveAccessToken(String username, String itemId, String accessToken) {
        // Update cache
        tokenCache.computeIfAbsent(username, k -> new HashMap<>()).put(itemId, accessToken);
        itemToUserCache.put(itemId, username);

        // Persist to S3
        persistTokens(username);
        persistItemToUser();

        System.out.println("Saved access token for user: " + username + ", itemId: " + itemId);
    }

    @Override
    public synchronized String getAccessToken(String username) {
        Map<String, String> tokens = listAccessTokens(username);
        if (tokens.isEmpty()) return null;
        return tokens.values().iterator().next();
    }

    @Override
    public synchronized String getAccessToken(String username, String itemId) {
        Map<String, String> tokens = listAccessTokens(username);
        return tokens.get(itemId);
    }

    @Override
    public synchronized Map<String, String> listAccessTokens(String username) {
        // Check cache first
        if (tokenCache.containsKey(username)) {
            return new HashMap<>(tokenCache.get(username));
        }

        // Load from S3
        try {
            String key = TOKENS_PREFIX + username + ".json";
            String json = readS3Object(key);
            if (json != null) {
                Map<String, String> tokens = objectMapper.readValue(json,
                    new TypeReference<Map<String, String>>() {});
                tokenCache.put(username, new HashMap<>(tokens));
                // Also update itemToUser cache
                for (String itemId : tokens.keySet()) {
                    itemToUserCache.put(itemId, username);
                }
                return new HashMap<>(tokens);
            }
        } catch (Exception e) {
            System.err.println("Error loading tokens from S3 for user " + username + ": " + e.getMessage());
        }

        return Map.of();
    }

    @Override
    public synchronized String usernameForItem(String itemId) {
        // Check cache first
        if (itemToUserCache.containsKey(itemId)) {
            return itemToUserCache.get(itemId);
        }

        // Load from S3
        try {
            String json = readS3Object(TOKENS_PREFIX + "item-to-user.json");
            if (json != null) {
                Map<String, String> mapping = objectMapper.readValue(json,
                    new TypeReference<Map<String, String>>() {});
                itemToUserCache.putAll(mapping);
                return itemToUserCache.get(itemId);
            }
        } catch (Exception e) {
            System.err.println("Error loading item-to-user mapping: " + e.getMessage());
        }

        return null;
    }

    @Override
    public synchronized void saveSelectedAccounts(String username, String itemId, List<String> accountIds) {
        selectedAccountsCache
            .computeIfAbsent(username, k -> new HashMap<>())
            .put(itemId, new ArrayList<>(accountIds));

        persistSelectedAccounts(username);
        System.out.println("Saved selected accounts for user: " + username + ", itemId: " + itemId);
    }

    @Override
    public synchronized List<String> getSelectedAccounts(String username, String itemId) {
        // Check cache
        if (selectedAccountsCache.containsKey(username)) {
            Map<String, List<String>> userAccounts = selectedAccountsCache.get(username);
            if (userAccounts.containsKey(itemId)) {
                return new ArrayList<>(userAccounts.get(itemId));
            }
        }

        // Load from S3
        try {
            String key = ACCOUNTS_PREFIX + username + ".json";
            String json = readS3Object(key);
            if (json != null) {
                Map<String, List<String>> accounts = objectMapper.readValue(json,
                    new TypeReference<Map<String, List<String>>>() {});
                selectedAccountsCache.put(username, new HashMap<>(accounts));
                List<String> result = accounts.get(itemId);
                return result != null ? new ArrayList<>(result) : List.of();
            }
        } catch (Exception e) {
            System.err.println("Error loading selected accounts from S3: " + e.getMessage());
        }

        return List.of();
    }

    // --- S3 persistence helpers ---

    private void persistTokens(String username) {
        try {
            Map<String, String> tokens = tokenCache.get(username);
            if (tokens == null) return;

            String key = TOKENS_PREFIX + username + ".json";
            String json = objectMapper.writeValueAsString(tokens);
            writeS3Object(key, json);
        } catch (Exception e) {
            System.err.println("Error persisting tokens to S3: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void persistItemToUser() {
        try {
            String key = TOKENS_PREFIX + "item-to-user.json";
            String json = objectMapper.writeValueAsString(itemToUserCache);
            writeS3Object(key, json);
        } catch (Exception e) {
            System.err.println("Error persisting item-to-user mapping: " + e.getMessage());
        }
    }

    private void persistSelectedAccounts(String username) {
        try {
            Map<String, List<String>> accounts = selectedAccountsCache.get(username);
            if (accounts == null) return;

            String key = ACCOUNTS_PREFIX + username + ".json";
            String json = objectMapper.writeValueAsString(accounts);
            writeS3Object(key, json);
        } catch (Exception e) {
            System.err.println("Error persisting selected accounts to S3: " + e.getMessage());
        }
    }

    private String readS3Object(String key) {
        try {
            GetObjectRequest request = GetObjectRequest.builder()
                .bucket(BUCKET_NAME)
                .key(key)
                .build();

            byte[] bytes = s3Client.getObjectAsBytes(request).asByteArray();
            return new String(bytes, StandardCharsets.UTF_8);
        } catch (NoSuchKeyException e) {
            // File doesn't exist yet, that's OK
            return null;
        } catch (Exception e) {
            System.err.println("Error reading S3 object " + key + ": " + e.getMessage());
            return null;
        }
    }

    private void writeS3Object(String key, String content) {
        try {
            PutObjectRequest request = PutObjectRequest.builder()
                .bucket(BUCKET_NAME)
                .key(key)
                .contentType("application/json")
                .build();

            s3Client.putObject(request, RequestBody.fromString(content, StandardCharsets.UTF_8));
        } catch (Exception e) {
            System.err.println("Error writing S3 object " + key + ": " + e.getMessage());
            throw new RuntimeException("Failed to persist to S3", e);
        }
    }
}
