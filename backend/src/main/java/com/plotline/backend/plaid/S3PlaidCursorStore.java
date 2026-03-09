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
 * S3-backed PlaidCursorStore that persists sync cursors and seen transactions.
 * Survives backend restarts/redeployments.
 */
@Component
@Primary
public class S3PlaidCursorStore implements PlaidCursorStore {
    private static final String BUCKET_NAME = "plotline-database-bucket";
    private static final String CURSORS_PREFIX = "plaid/cursors/";
    private static final String SEEN_TXN_PREFIX = "plaid/seen-txns/";

    private final S3Client s3Client;
    private final ObjectMapper objectMapper = new ObjectMapper();

    // In-memory cache
    private final Map<String, String> cursorCache = new ConcurrentHashMap<>(); // key: user|item -> cursor
    private final Set<String> seenTxnCache = ConcurrentHashMap.newKeySet(); // key: user|item|txn
    private final Set<String> loadedSeenTxnUsers = ConcurrentHashMap.newKeySet(); // users we've loaded seen txns for

    public S3PlaidCursorStore() {
        Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();

        String accessKey = System.getenv("AWS_ACCESS_KEY_ID");
        String secretKey = System.getenv("AWS_SECRET_ACCESS_KEY");
        String region = System.getenv("AWS_REGION");

        if (accessKey == null || accessKey.isBlank()) accessKey = dotenv.get("AWS_ACCESS_KEY_ID");
        if (secretKey == null || secretKey.isBlank()) secretKey = dotenv.get("AWS_SECRET_ACCESS_KEY");
        if (region == null || region.isBlank()) region = dotenv.get("AWS_REGION");

        this.s3Client = S3Client.builder()
            .region(Region.of(region))
            .credentialsProvider(StaticCredentialsProvider.create(
                AwsBasicCredentials.create(accessKey, secretKey)))
            .build();

        System.out.println("S3PlaidCursorStore initialized - cursors will persist across restarts");
    }

    private static String cursorKey(String username, String itemId) {
        return username + "|" + itemId;
    }

    private static String txnKey(String username, String itemId, String transactionId) {
        return username + "|" + itemId + "|" + transactionId;
    }

    @Override
    public synchronized String getCursor(String username, String itemId) {
        String key = cursorKey(username, itemId);

        // Check cache
        if (cursorCache.containsKey(key)) {
            return cursorCache.get(key);
        }

        // Load from S3
        try {
            String s3Key = CURSORS_PREFIX + username + ".json";
            String json = readS3Object(s3Key);
            if (json != null) {
                Map<String, String> cursors = objectMapper.readValue(json,
                    new TypeReference<Map<String, String>>() {});
                // Cache all cursors for this user
                for (var entry : cursors.entrySet()) {
                    cursorCache.put(cursorKey(username, entry.getKey()), entry.getValue());
                }
                return cursorCache.get(key);
            }
        } catch (Exception e) {
            System.err.println("Error loading cursor from S3: " + e.getMessage());
        }

        return null;
    }

    @Override
    public synchronized void saveCursor(String username, String itemId, String cursor) {
        String key = cursorKey(username, itemId);
        cursorCache.put(key, cursor);
        persistCursors(username);
    }

    @Override
    public synchronized boolean hasSeenTxn(String username, String itemId, String transactionId) {
        String key = txnKey(username, itemId, transactionId);

        // Make sure we've loaded this user's seen transactions
        loadSeenTxnsIfNeeded(username);

        return seenTxnCache.contains(key);
    }

    @Override
    public synchronized void markSeenTxn(String username, String itemId, String transactionId) {
        String key = txnKey(username, itemId, transactionId);
        seenTxnCache.add(key);
        persistSeenTxns(username);
    }

    private void loadSeenTxnsIfNeeded(String username) {
        if (loadedSeenTxnUsers.contains(username)) {
            return;
        }

        try {
            String s3Key = SEEN_TXN_PREFIX + username + ".json";
            String json = readS3Object(s3Key);
            if (json != null) {
                Set<String> txns = objectMapper.readValue(json,
                    new TypeReference<Set<String>>() {});
                seenTxnCache.addAll(txns);
            }
            loadedSeenTxnUsers.add(username);
        } catch (Exception e) {
            System.err.println("Error loading seen txns from S3: " + e.getMessage());
            loadedSeenTxnUsers.add(username); // Mark as loaded to avoid repeated failures
        }
    }

    private void persistCursors(String username) {
        try {
            // Collect all cursors for this user
            Map<String, String> userCursors = new HashMap<>();
            String prefix = username + "|";
            for (var entry : cursorCache.entrySet()) {
                if (entry.getKey().startsWith(prefix)) {
                    String itemId = entry.getKey().substring(prefix.length());
                    userCursors.put(itemId, entry.getValue());
                }
            }

            String s3Key = CURSORS_PREFIX + username + ".json";
            String json = objectMapper.writeValueAsString(userCursors);
            writeS3Object(s3Key, json);
        } catch (Exception e) {
            System.err.println("Error persisting cursors to S3: " + e.getMessage());
        }
    }

    private void persistSeenTxns(String username) {
        try {
            // Collect all seen txns for this user
            Set<String> userTxns = new HashSet<>();
            String prefix = username + "|";
            for (String key : seenTxnCache) {
                if (key.startsWith(prefix)) {
                    userTxns.add(key);
                }
            }

            String s3Key = SEEN_TXN_PREFIX + username + ".json";
            String json = objectMapper.writeValueAsString(userTxns);
            writeS3Object(s3Key, json);
        } catch (Exception e) {
            System.err.println("Error persisting seen txns to S3: " + e.getMessage());
        }
    }

    @Override
    public synchronized void clearSyncState(String username) {
        System.out.println("Clearing all sync state for user: " + username);

        // Clear cursor cache entries for this user
        String prefix = username + "|";
        cursorCache.entrySet().removeIf(entry -> entry.getKey().startsWith(prefix));

        // Clear seen transaction cache entries for this user
        seenTxnCache.removeIf(key -> key.startsWith(prefix));

        // Remove from loaded users set so it can be reloaded fresh
        loadedSeenTxnUsers.remove(username);

        // Delete S3 objects for this user
        try {
            deleteS3Object(CURSORS_PREFIX + username + ".json");
            System.out.println("Deleted cursor file from S3 for user: " + username);
        } catch (Exception e) {
            System.err.println("Error deleting cursor file from S3: " + e.getMessage());
        }

        try {
            deleteS3Object(SEEN_TXN_PREFIX + username + ".json");
            System.out.println("Deleted seen transactions file from S3 for user: " + username);
        } catch (Exception e) {
            System.err.println("Error deleting seen txns file from S3: " + e.getMessage());
        }

        System.out.println("Sync state cleared for user: " + username + " - next sync will fetch all transactions");
    }

    private void deleteS3Object(String key) {
        try {
            DeleteObjectRequest request = DeleteObjectRequest.builder()
                .bucket(BUCKET_NAME)
                .key(key)
                .build();
            s3Client.deleteObject(request);
        } catch (Exception e) {
            // Ignore if object doesn't exist
            if (!e.getMessage().contains("NoSuchKey")) {
                System.err.println("Error deleting S3 object " + key + ": " + e.getMessage());
            }
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
        }
    }
}
