package com.plotline.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.plotline.backend.dto.GroceryItem;
import com.plotline.backend.dto.GroceryList;
import com.plotline.backend.dto.GroceryListInvite;
import com.twilio.rest.chat.v1.service.User;

import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Object;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;

import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TimeZone;
import java.util.UUID;

@Service
public class GroceryListService {

    private final S3Client s3Client;
    private final String BUCKET_NAME = "plotline-database-bucket";

    private final UserProfileService userProfileService;

    public GroceryListService(S3Client s3Client, UserProfileService userProfileService) {
        this.s3Client = s3Client;
        this.userProfileService = userProfileService;
    }

    private String normalize(String username) {
        return username == null ? "" : username.trim().toLowerCase();
    }

    private long daysSinceCreated(String createdAt) {
        if (createdAt == null || createdAt.isEmpty()) return 0;
        try {
            SimpleDateFormat iso = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
            iso.setTimeZone(TimeZone.getTimeZone("UTC"));
            Date date = iso.parse(createdAt);
            return (System.currentTimeMillis() - date.getTime()) / (1000L * 60 * 60 * 24);
        } catch (Exception e) {
            try {
                long epochMs = Long.parseLong(createdAt);
                return (System.currentTimeMillis() - epochMs) / (1000L * 60 * 60 * 24);
            } catch (Exception e2) {
                return 0;
            }
        }
    }

    // Helper function to construct the S3 path for the grocery list items
    private String getS3Path(String username, String listId) {
        String normUser = normalize(username);
        return "users/" + normUser + "/grocery/lists/" + listId.toUpperCase() + ".json";
    }

    // ── Shared-list resolution ─────────────────────────────────────────────────
    // Shared lists have a single canonical copy owned by the creator. Members hold
    // a lightweight pointer file that records which user owns the canonical list.

    private String sharedPointerPath(String username, String listId) {
        String normUser = normalize(username);
        return "users/" + normUser + "/grocery/shared/" + listId.toUpperCase() + ".json";
    }

    private boolean s3ObjectExists(String key) {
        try {
            s3Client.headObject(b -> b.bucket(BUCKET_NAME).key(key));
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    // Resolve the username that owns the canonical copy of a list for the acting user.
    // Returns the acting user if they own it directly, otherwise the owner recorded in
    // their shared pointer, or null if the list is not accessible to them.
    private String resolveOwnerUsername(String actingUser, String listId) {
        String normUser = normalize(actingUser);
        if (s3ObjectExists(getS3Path(normUser, listId))) {
            return normUser;
        }
        // Fast path: read the pointer at its expected key
        try {
            var stream = s3Client.getObject(b -> b.bucket(BUCKET_NAME).key(sharedPointerPath(normUser, listId)));
            JsonNode pointer = objectMapper.readTree(stream.readAllBytes());
            if (pointer.hasNonNull("ownerUsername")) {
                return normalize(pointer.get("ownerUsername").asText());
            }
        } catch (Exception ignored) {}

        // Robust fallback: scan all of the user's shared pointers and match by listId,
        // case-insensitively. Tolerates any key-format drift between how a pointer was
        // written and how we construct the lookup key.
        try {
            String prefix = "users/" + normUser + "/grocery/shared/";
            var pointers = s3Client.listObjectsV2(ListObjectsV2Request.builder()
                    .bucket(BUCKET_NAME).prefix(prefix).build()).contents();
            for (var ptr : pointers) {
                try {
                    var stream = s3Client.getObject(b -> b.bucket(BUCKET_NAME).key(ptr.key()));
                    JsonNode pointer = objectMapper.readTree(stream.readAllBytes());
                    String ptrListId = pointer.hasNonNull("listId") ? pointer.get("listId").asText() : "";
                    if (ptrListId.equalsIgnoreCase(listId) && pointer.hasNonNull("ownerUsername")) {
                        return normalize(pointer.get("ownerUsername").asText());
                    }
                } catch (Exception ignored) {}
            }
        } catch (Exception ignored) {}

        return null;
    }

    // Resolve the canonical S3 key for a list the acting user can access, or null.
    private String resolveCanonicalPath(String actingUser, String listId) {
        String owner = resolveOwnerUsername(actingUser, listId);
        return owner == null ? null : getS3Path(owner, listId);
    }

    // Write a member's pointer to a canonical shared list.
    private void writeSharedPointer(String memberUsername, String ownerUsername, String listId, String listName)
            throws IOException {
        Map<String, String> pointer = new HashMap<>();
        pointer.put("ownerUsername", normalize(ownerUsername));
        pointer.put("listId", listId);
        pointer.put("listName", listName);
        s3Client.putObject(
                PutObjectRequest.builder().bucket(BUCKET_NAME).key(sharedPointerPath(memberUsername, listId)).build(),
                RequestBody.fromString(objectMapper.writeValueAsString(pointer)));
    }

    // Remove the acting user from a shared list (leave). Deletes their pointer and
    // drops their membership from the canonical list. Safe to call for owners (no-op).
    private void leaveSharedList(String actingUser, String listId) throws IOException {
        String normUser = normalize(actingUser);
        String owner = resolveOwnerUsername(normUser, listId);
        if (owner != null && !owner.equals(normUser)) {
            String canonicalKey = getS3Path(owner, listId);
            synchronized (lockFor(canonicalKey)) {
                GroceryList canonical = getGroceryList(owner, listId);
                if (canonical != null && canonical.getMembers() != null) {
                    canonical.getMembers().removeIf(m -> normalize(m).equals(normUser));
                    canonical.setUpdatedAt(nowIso());
                    writeListAtPath(canonicalKey, canonical);
                }
            }
        }
        s3Client.deleteObject(DeleteObjectRequest.builder().bucket(BUCKET_NAME)
                .key(sharedPointerPath(normUser, listId)).build());
    }

    // ── Concurrency-safe read-modify-write ─────────────────────────────────────
    // Multiple members can edit the same shared list at once. Each edit reads the
    // whole canonical file, changes it, and writes it back, so overlapping edits could
    // clobber each other. We serialize edits to the same list with an in-process lock
    // keyed by the canonical S3 path. NOTE: this protects a single backend instance; if
    // the app is ever scaled to multiple instances, true safety needs S3 conditional
    // writes (If-Match), which this SDK version doesn't support.
    private final java.util.concurrent.ConcurrentHashMap<String, Object> listLocks =
            new java.util.concurrent.ConcurrentHashMap<>();

    private Object lockFor(String key) {
        return listLocks.computeIfAbsent(key, k -> new Object());
    }

    private String nowIso() {
        SimpleDateFormat iso = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
        iso.setTimeZone(TimeZone.getTimeZone("UTC"));
        return iso.format(new Date());
    }

    private GroceryList readListAtPath(String s3Path) throws IOException {
        ResponseInputStream<GetObjectResponse> response = s3Client.getObject(
                GetObjectRequest.builder().bucket(BUCKET_NAME).key(s3Path).build());
        return objectMapper.readValue(response, GroceryList.class);
    }

    private void writeListAtPath(String s3Path, GroceryList list) throws IOException {
        String json = objectMapper.writeValueAsString(list);
        s3Client.putObject(PutObjectRequest.builder().bucket(BUCKET_NAME).key(s3Path).build(),
                RequestBody.fromString(json));
    }

    @FunctionalInterface
    private interface ListMutation {
        // Return true if the list was changed and should be persisted.
        boolean apply(GroceryList list);
    }

    // Atomically read the canonical list, apply a change, and write it back — all under a
    // per-list lock so concurrent edits to a shared list don't overwrite one another.
    private boolean mutateCanonical(String username, String listId, ListMutation mutation) {
        String s3Path = resolveCanonicalPath(username, listId);
        if (s3Path == null) return false;
        synchronized (lockFor(s3Path)) {
            try {
                GroceryList list = readListAtPath(s3Path);
                if (list == null) return false;
                if (!mutation.apply(list)) return false;
                list.setUpdatedAt(nowIso());
                writeListAtPath(s3Path, list);
                return true;
            } catch (Exception e) {
                e.printStackTrace();
                return false;
            }
        }
    }

    // Method to fetch a grocery list from S3
    public GroceryList getGroceryList(String username, String listId) {
        try {
            // Resolve to the canonical copy (owned by the acting user or a friend who shared it)
            String s3Path = resolveCanonicalPath(username, listId);
            if (s3Path == null) return null;

            // Fetch the grocery list from S3
            GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(s3Path)
                    .build();

            ResponseInputStream<GetObjectResponse> response = s3Client.getObject(getObjectRequest);

            // Parse the grocery list JSON into a GroceryList object
            return objectMapper.readValue(response, GroceryList.class);

        } catch (Exception e) {
            e.printStackTrace();
            return null;  // Return null if the list doesn't exist or an error occurs
        }
    }

    // Method to check if a grocery list already exists for the user (based on name)
    public boolean doesGroceryListExist(String username, String groceryListName) {
        String normUser = normalize(username);
        if (groceryListName == null) return false;
        String target = groceryListName.trim().toLowerCase();

        // List all list files for the user and compare their actual names. (The S3 key
        // is a UUID, not the name, so the name lives inside each JSON file.)
        String prefix = "users/" + normUser + "/grocery/lists/";
        var objectSummaries = s3Client.listObjectsV2(ListObjectsV2Request.builder()
                .bucket(BUCKET_NAME).prefix(prefix).build()).contents();

        for (var summary : objectSummaries) {
            try {
                GroceryList existing = readListAtPath(summary.key());
                if (existing != null && existing.getName() != null
                        && existing.getName().trim().equalsIgnoreCase(target)) {
                    return true;
                }
            } catch (Exception ignored) {}
        }
        return false;
    }

    // Method to create and save a grocery list to S3 in JSON format
    public String createGroceryList(GroceryList groceryList, String username) throws IOException {
        String normUserCheck = normalize(username);
        String activePrefix = "users/" + normUserCheck + "/grocery/lists/";
        int activeCount = s3Client.listObjectsV2(ListObjectsV2Request.builder()
                .bucket(BUCKET_NAME).prefix(activePrefix).build()).contents().size();
        if (activeCount >= 10) {
            throw new IllegalArgumentException(
                "You've reached the limit of 10 active grocery lists. Archive or delete a list before creating a new one.");
        }

        // Check if the grocery list with the same name already exists for the user
        if (doesGroceryListExist(username, groceryList.getName())) {
            throw new IllegalArgumentException("A grocery list with this name already exists.");
        }

        String groceryListID = groceryList.getId() != null ? groceryList.getId() : UUID.randomUUID().toString().toUpperCase();

        groceryList.setId(groceryListID);

        // The creator owns the canonical copy; it starts with no other members
        groceryList.setOwnerUsername(normalize(username));
        if (groceryList.getMembers() == null) {
            groceryList.setMembers(new ArrayList<>());
        }

        // Set createdAt and updatedAt to the current date-time
        String currentDate = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());
        groceryList.setCreatedAt(currentDate);
        groceryList.setUpdatedAt(currentDate);

        // Serialize the GroceryList object to JSON
        ObjectMapper objectMapper = new ObjectMapper();
        String jsonString = objectMapper.writeValueAsString(groceryList);

        String normUser = normalize(username);
        // Use the new path structure
        String s3Key = "users/" + normUser + "/grocery/lists/" + groceryListID + ".json";

        // Create a PutObjectRequest with the bucket name, S3 key, and content
        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(BUCKET_NAME)
                .key(s3Key)
                .build();
        s3Client.putObject(putObjectRequest, RequestBody.fromBytes(jsonString.getBytes()));

        // Update the user's trophy progress for creating a grocery list
        userProfileService.incrementTrophy(normUser, "grocery-lists", 1);

        return groceryListID;  // Return the key of the uploaded object (i.e., the S3 file path)
    }

    // Fetch all grocery lists for a specific user from S3
    public List<GroceryList> getGroceryListsForUser(String username) throws IOException {
        List<GroceryList> groceryLists = new ArrayList<>();

        String normUser = normalize(username);
        // Construct the S3 key path to list all grocery lists for the user
        String s3Path = "users/" + normUser + "/grocery/lists/";

        // List all objects in the grocery lists folder for the user
        ListObjectsV2Request listObjectsV2Request = ListObjectsV2Request.builder()
                .bucket(BUCKET_NAME)
                .prefix(s3Path)
                .build();

        var objectSummaries = s3Client.listObjectsV2(listObjectsV2Request).contents();

        for (S3Object object : objectSummaries) {
            String key = object.key();
            var s3Object = s3Client.getObject(b -> b.bucket(BUCKET_NAME).key(key));
            var objectContent = new String(s3Object.readAllBytes());

            ObjectMapper objectMapper = new ObjectMapper();
            GroceryList groceryList = objectMapper.readValue(objectContent, GroceryList.class);

            boolean isShared = groceryList.getMembers() != null && !groceryList.getMembers().isEmpty();

            // Auto-archive lists older than 14 days (never auto-archive shared lists —
            // that would strand other members' access to the canonical copy)
            if (!isShared && daysSinceCreated(groceryList.getCreatedAt()) >= 14) {
                try {
                    archiveGroceryList(groceryList, username);
                } catch (Exception e) {
                    groceryLists.add(groceryList); // Archive failed — still show it
                }
            } else {
                groceryLists.add(groceryList);
            }
        }

        // Include lists shared with this user (canonical copies owned by friends)
        String sharedPrefix = "users/" + normUser + "/grocery/shared/";
        var sharedPointers = s3Client.listObjectsV2(ListObjectsV2Request.builder()
                .bucket(BUCKET_NAME).prefix(sharedPrefix).build()).contents();

        for (S3Object ptr : sharedPointers) {
            try {
                var ptrStream = s3Client.getObject(b -> b.bucket(BUCKET_NAME).key(ptr.key()));
                JsonNode pointer = objectMapper.readTree(ptrStream.readAllBytes());
                String owner = normalize(pointer.get("ownerUsername").asText());
                String sharedListId = pointer.get("listId").asText();

                GroceryList shared = getGroceryList(owner, sharedListId);
                if (shared != null) {
                    groceryLists.add(shared);
                } else {
                    // Canonical copy was deleted by the owner — clean up the stale pointer
                    s3Client.deleteObject(DeleteObjectRequest.builder()
                            .bucket(BUCKET_NAME).key(ptr.key()).build());
                }
            } catch (Exception ignored) {}
        }

        return groceryLists;
    }

    private ObjectMapper objectMapper = new ObjectMapper();

    public List<GroceryItem> getItems(String username, String listId) {
    try {
        // Resolve to the canonical copy so members see the same items as the owner
        String s3Path = resolveCanonicalPath(username, listId);
        if (s3Path == null) return new ArrayList<>();

        // Get the grocery list from S3
        GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                .bucket(BUCKET_NAME)
                .key(s3Path)
                .build();

        ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
        String jsonContent = objectBytes.asUtf8String();

        // Parse the JSON to get the grocery list
        ObjectMapper mapper = new ObjectMapper();
        GroceryList groceryList = mapper.readValue(jsonContent, GroceryList.class);

        // Return the items from the grocery list
        return groceryList.getItems();
    } catch (Exception e) {
        e.printStackTrace();
        return new ArrayList<>(); // Return empty list on error
    }
}

    // Add an item to the grocery list (atomic read-modify-write on the canonical copy)
    public boolean addItem(String username, String listId, GroceryItem item) {
        return mutateCanonical(username, listId, list -> {
            if (list.getItems() == null) list.setItems(new ArrayList<>());
            list.getItems().add(item);
            return true;
        });
    }

    // Delete an item from the grocery list
    public boolean deleteItem(String username, String listId, String itemId) {
        return mutateCanonical(username, listId, list ->
                list.getItems() != null && list.getItems().removeIf(it -> it.getId().equals(itemId)));
    }

    // Toggle the checked status of a grocery item, recording who checked it off
    public boolean toggleChecked(String username, String listId, String itemId) {
        String actor = normalize(username);
        return mutateCanonical(username, listId, list -> {
            if (list.getItems() == null) return false;
            for (GroceryItem it : list.getItems()) {
                if (it.getId().toString().equals(itemId)) {
                    boolean nowChecked = !it.isChecked();
                    it.setChecked(nowChecked);
                    it.setCheckedBy(nowChecked ? actor : null);
                    return true;
                }
            }
            return false;
        });
    }

    // Update an item's information in the grocery list
    public boolean updateItemDetails(String username, String listId, GroceryItem updatedItem) {
        return mutateCanonical(username, listId, list -> {
            if (list.getItems() == null) return false;
            for (GroceryItem it : list.getItems()) {
                if (it.getId().equals(updatedItem.getId())) {
                    it.setName(updatedItem.getName());
                    it.setQuantity(updatedItem.getQuantity());
                    it.setChecked(updatedItem.isChecked());
                    it.setPrice(updatedItem.getPrice());
                    it.setStore(updatedItem.getStore());
                    it.setNotes(updatedItem.getNotes());
                    return true;
                }
            }
            return false;
        });
    }

    // Delete a grocery list. If the acting user owns the canonical copy, delete it and
    // clean up every member's pointer. If the acting user is only a member, this leaves
    // the shared list (removes their pointer + membership) without affecting others.
    public boolean deleteGroceryList(String username, String listId) {
        try {
            String normUser = normalize(username);
            String ownKey = getS3Path(normUser, listId);

            // Case 1: acting user owns the canonical list
            if (s3ObjectExists(ownKey)) {
                synchronized (lockFor(ownKey)) {
                    GroceryList list = getGroceryList(normUser, listId);
                    if (list != null && list.getMembers() != null) {
                        for (String member : list.getMembers()) {
                            s3Client.deleteObject(DeleteObjectRequest.builder().bucket(BUCKET_NAME)
                                    .key(sharedPointerPath(member, listId)).build());
                        }
                    }
                    s3Client.deleteObject(DeleteObjectRequest.builder().bucket(BUCKET_NAME).key(ownKey).build());
                }
                return true;
            }

            // Case 2: acting user is a member — leave the shared list
            if (s3ObjectExists(sharedPointerPath(normUser, listId))) {
                leaveSharedList(normUser, listId);
                return true;
            }

            return false;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    public void deleteArchivedGroceryList(String username, String listId) {
        String normUser = normalize(username);
        String s3Path = "users/" + normUser + "/grocery/archived/" + listId.toUpperCase() + ".json";
        s3Client.deleteObject(DeleteObjectRequest.builder()
                .bucket(BUCKET_NAME).key(s3Path).build());
    }

    public void deleteAllArchivedGroceryLists(String username) {
        String normUser = normalize(username);
        String prefix = "users/" + normUser + "/grocery/archived/";
        var objects = s3Client.listObjectsV2(ListObjectsV2Request.builder()
                .bucket(BUCKET_NAME).prefix(prefix).build()).contents();
        for (var obj : objects) {
            s3Client.deleteObject(DeleteObjectRequest.builder()
                    .bucket(BUCKET_NAME).key(obj.key()).build());
        }
    }

    // Method to archive a grocery list to S3 in JSON format
    public String archiveGroceryList(GroceryList groceryList, String username) throws IOException {
        // Ensure the list exists before attempting to archive
        if (groceryList.getId() == null) {
            throw new IllegalArgumentException("Grocery list ID is required.");
        }

        String groceryListID = groceryList.getId();
        String normUser = normalize(username);

        // If the acting user is only a member of a shared list (not the owner), archiving
        // shouldn't fork a private snapshot — leave the shared list instead.
        if (!s3ObjectExists(getS3Path(normUser, groceryListID))
                && s3ObjectExists(sharedPointerPath(normUser, groceryListID))) {
            leaveSharedList(normUser, groceryListID);
            return sharedPointerPath(normUser, groceryListID);
        }

        // Serialize the GroceryList object to JSON
        ObjectMapper objectMapper = new ObjectMapper();
        String jsonString = objectMapper.writeValueAsString(groceryList);

        // Define the source and destination S3 keys
        String sourceKey = "users/" + normUser + "/grocery/lists/" + groceryListID + ".json";
        String destinationKey = "users/" + normUser + "/grocery/archived/" + groceryListID + ".json";

        // Copy the grocery list from the original folder to the archived folder
        try {
            // Upload to archived folder
            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(destinationKey)
                    .build();
            s3Client.putObject(putObjectRequest, RequestBody.fromBytes(jsonString.getBytes()));

            // Delete the original grocery list from the "grocery/lists" folder
            DeleteObjectRequest deleteObjectRequest = DeleteObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(sourceKey)
                    .build();
            s3Client.deleteObject(deleteObjectRequest);

            // If this was a shared list, clean up members' pointers so they don't dangle
            if (groceryList.getMembers() != null) {
                for (String member : groceryList.getMembers()) {
                    s3Client.deleteObject(DeleteObjectRequest.builder().bucket(BUCKET_NAME)
                            .key(sharedPointerPath(member, groceryListID)).build());
                }
            }

            return destinationKey;  // Return the new S3 path of the archived list
        } catch (Exception e) {
            e.printStackTrace();
            throw new IOException("Failed to archive the grocery list", e);
        }
    }

    // Method to retrieve archived grocery lists from S3
    public List<GroceryList> getArchivedGroceryLists(String username) throws IOException {
        List<GroceryList> archivedLists = new ArrayList<>();

        String normUser = normalize(username);
        // Construct the S3 key path to list all archived grocery lists for the user
        String s3Path = "users/" + normUser + "/grocery/archived/";

        // List all objects in the archived grocery lists folder for the user
        ListObjectsV2Request listObjectsV2Request = ListObjectsV2Request.builder()
                .bucket(BUCKET_NAME)
                .prefix(s3Path)
                .build();

        var objectSummaries = s3Client.listObjectsV2(listObjectsV2Request).contents();

        // Archived lists are kept for 7 days, then permanently auto-deleted. The object's
        // lastModified time is when it was archived, so we use it as the retention clock.
        long sevenDaysMs = 7L * 24 * 60 * 60 * 1000;

        // For each archived grocery list file, read and parse the content
        for (S3Object object : objectSummaries) {
            String key = object.key();

            // Auto-delete archived lists older than 7 days
            if (object.lastModified() != null
                    && (System.currentTimeMillis() - object.lastModified().toEpochMilli()) >= sevenDaysMs) {
                try {
                    s3Client.deleteObject(DeleteObjectRequest.builder().bucket(BUCKET_NAME).key(key).build());
                } catch (Exception ignored) {}
                continue; // don't return an expired list
            }

            var s3Object = s3Client.getObject(b -> b.bucket(BUCKET_NAME).key(key));
            var objectContent = new String(s3Object.readAllBytes());  // Read the content as a String

            // Convert the JSON content to a GroceryList object
            ObjectMapper objectMapper = new ObjectMapper();
            GroceryList groceryList = objectMapper.readValue(objectContent, GroceryList.class);
            archivedLists.add(groceryList);
        }

        return archivedLists;
    }

    // Method to restore an archived grocery list, unchecking all items
    public String restoreArchivedGroceryList(GroceryList groceryList, String username) throws IOException {
        // Ensure the list exists before attempting to restore
        if (groceryList.getId() == null) {
            throw new IllegalArgumentException("Grocery list ID is required.");
        }

        // Uncheck all items in the grocery list
        for (GroceryItem item : groceryList.getItems()) {
            item.setChecked(false);   // Set each item's checked status to false
            item.setCheckedBy(null);  // Clear who-checked attribution on restore
        }

        // Restore as a fresh private list owned by the restorer. Any prior shared
        // members' pointers were removed when it was archived, so keeping the old member
        // list would show phantom members who can no longer see it.
        groceryList.setOwnerUsername(normalize(username));
        groceryList.setMembers(new ArrayList<>());

        String groceryListID = groceryList.getId();

        // Serialize the GroceryList object to JSON
        ObjectMapper objectMapper = new ObjectMapper();
        String jsonString = objectMapper.writeValueAsString(groceryList);

        String normUser = normalize(username);
        // Define the source and destination S3 keys
        String sourceKey = "users/" + normUser + "/grocery/archived/" + groceryListID + ".json";
        String destinationKey = "users/" + normUser + "/grocery/lists/" + groceryListID + ".json";

        // Copy the grocery list from the archived folder to the original folder
        try {
            // Upload to the original folder
            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(destinationKey)
                    .build();
            s3Client.putObject(putObjectRequest, RequestBody.fromBytes(jsonString.getBytes()));

            // Delete the original grocery list from the "grocery/archived" folder
            DeleteObjectRequest deleteObjectRequest = DeleteObjectRequest.builder()
                    .bucket(BUCKET_NAME)
                    .key(sourceKey)
                    .build();
            s3Client.deleteObject(deleteObjectRequest);

            return destinationKey;  // Return the new S3 path of the restored list
        } catch (Exception e) {
            e.printStackTrace();
            throw new IOException("Failed to restore the grocery list", e);
        }
    }

    // ── Grocery List Sharing ──────────────────────────────────────────────────

    private String inviteSentPath(String normUser, String inviteId) {
        return "users/" + normUser + "/grocery/invites/sent/" + inviteId + ".json";
    }

    private String inviteReceivedPath(String normUser, String inviteId) {
        return "users/" + normUser + "/grocery/invites/received/" + inviteId + ".json";
    }

    public GroceryListInvite shareGroceryList(String fromUsername, String toUsername, String listId) throws IOException {
        String normFrom = normalize(fromUsername);
        String normTo   = normalize(toUsername);

        GroceryList list = getGroceryList(normFrom, listId);
        if (list == null) throw new IllegalArgumentException("Grocery list not found.");

        // Only the list owner may share it (owner-only sharing)
        String ownerUsername = resolveOwnerUsername(normFrom, listId);
        if (ownerUsername == null) ownerUsername = normFrom;
        if (!normFrom.equals(ownerUsername)) {
            throw new IllegalArgumentException("Only the list owner can share this list.");
        }

        // Don't invite the owner or an existing member back onto their own list
        if (normTo.equals(ownerUsername)) {
            throw new IllegalArgumentException("This user already owns the list.");
        }
        if (list.getMembers() != null && list.getMembers().stream().anyMatch(m -> normalize(m).equals(normTo))) {
            throw new IllegalArgumentException("This user is already on the list.");
        }

        String inviteId = UUID.randomUUID().toString().toUpperCase();
        String now = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(new Date());

        GroceryListInvite invite = new GroceryListInvite();
        invite.setId(inviteId);
        invite.setFromUsername(fromUsername);
        invite.setToUsername(toUsername);
        invite.setOwnerUsername(ownerUsername);
        invite.setListId(listId);
        invite.setListName(list.getName());
        invite.setSentAt(now);
        invite.setItems(list.getItems());

        String json = objectMapper.writeValueAsString(invite);
        byte[] bytes = json.getBytes();

        s3Client.putObject(PutObjectRequest.builder().bucket(BUCKET_NAME).key(inviteSentPath(normFrom, inviteId)).build(),
                RequestBody.fromBytes(bytes));
        s3Client.putObject(PutObjectRequest.builder().bucket(BUCKET_NAME).key(inviteReceivedPath(normTo, inviteId)).build(),
                RequestBody.fromBytes(bytes));

        return invite;
    }

    public List<GroceryListInvite> getPendingGroceryInvites(String username) throws IOException {
        String normUser = normalize(username);
        String prefix = "users/" + normUser + "/grocery/invites/received/";
        List<GroceryListInvite> invites = new ArrayList<>();

        var objects = s3Client.listObjectsV2(ListObjectsV2Request.builder()
                .bucket(BUCKET_NAME).prefix(prefix).build()).contents();

        for (var obj : objects) {
            try {
                var stream = s3Client.getObject(b -> b.bucket(BUCKET_NAME).key(obj.key()));
                String content = new String(stream.readAllBytes());
                invites.add(objectMapper.readValue(content, GroceryListInvite.class));
            } catch (Exception ignored) {}
        }
        return invites;
    }

    public void respondToGroceryShare(String recipientUsername, String inviteId, boolean accept) throws IOException {
        String normRecipient = normalize(recipientUsername);

        String receivedKey = inviteReceivedPath(normRecipient, inviteId);
        var stream = s3Client.getObject(b -> b.bucket(BUCKET_NAME).key(receivedKey));
        String content = new String(stream.readAllBytes());
        GroceryListInvite invite = objectMapper.readValue(content, GroceryListInvite.class);

        String normSender = normalize(invite.getFromUsername());

        if (accept) {
            // Join the owner's canonical list as a member — no copy is made, so all
            // members read from and write to the same shared list.
            String owner = normalize(invite.getOwnerUsername() != null
                    ? invite.getOwnerUsername() : invite.getFromUsername());
            String listId = invite.getListId();
            String canonicalKey = getS3Path(owner, listId);

            // Serialize the membership change against concurrent edits to the same list
            String listName;
            synchronized (lockFor(canonicalKey)) {
                GroceryList canonical = getGroceryList(owner, listId);
                if (canonical == null) {
                    throw new IllegalArgumentException("The shared list no longer exists.");
                }

                // Add the recipient to the canonical member list (idempotent)
                List<String> members = canonical.getMembers() != null
                        ? canonical.getMembers() : new ArrayList<>();
                boolean alreadyMember = members.stream().anyMatch(m -> normalize(m).equals(normRecipient));
                if (!alreadyMember && !normRecipient.equals(owner)) {
                    members.add(recipientUsername);
                }
                canonical.setMembers(members);
                if (canonical.getOwnerUsername() == null) canonical.setOwnerUsername(owner);
                canonical.setUpdatedAt(nowIso());

                writeListAtPath(canonicalKey, canonical);
                listName = canonical.getName();
            }

            // Write the recipient's pointer to the canonical list
            writeSharedPointer(normRecipient, owner, listId, listName);
        }

        // Delete invite from both sides
        s3Client.deleteObject(DeleteObjectRequest.builder().bucket(BUCKET_NAME).key(receivedKey).build());
        s3Client.deleteObject(DeleteObjectRequest.builder().bucket(BUCKET_NAME)
                .key(inviteSentPath(normSender, inviteId)).build());
    }

    // Owner-only: remove a member from a shared list. Drops them from the canonical
    // member list and deletes their pointer so the list disappears from their view.
    public boolean unshareGroceryList(String ownerUsername, String listId, String memberUsername) throws IOException {
        String normOwner  = normalize(ownerUsername);
        String normMember = normalize(memberUsername);

        // Only the user who owns the canonical copy may remove members
        String canonicalKey = getS3Path(normOwner, listId);
        if (!s3ObjectExists(canonicalKey)) {
            return false;
        }

        synchronized (lockFor(canonicalKey)) {
            GroceryList canonical = getGroceryList(normOwner, listId);
            if (canonical == null) return false;

            if (canonical.getMembers() != null) {
                canonical.getMembers().removeIf(m -> normalize(m).equals(normMember));
                canonical.setUpdatedAt(nowIso());
                writeListAtPath(canonicalKey, canonical);
            }
        }

        // Remove the member's pointer to the shared list
        s3Client.deleteObject(DeleteObjectRequest.builder().bucket(BUCKET_NAME)
                .key(sharedPointerPath(normMember, listId)).build());

        return true;
    }

    public String generateGroceryListFromMeal(String mealName, String username, String rawOpenAIResponse) throws Exception {
        // Parse the raw JSON response from OpenAI
        ObjectMapper mapper = new ObjectMapper();
        List<GroceryItem> items = new ArrayList<>();
        JsonNode itemsArray;
        
        try {
            itemsArray = mapper.readTree(rawOpenAIResponse);
        } catch (Exception e) {
            throw new IllegalArgumentException("Invalid response format from AI service: " + e.getMessage());
        }
        
        // Generate a UUID for the list
        String listId = UUID.randomUUID().toString().toUpperCase();
        
        // Create grocery items from the items array
        for (JsonNode node : itemsArray) {
            GroceryItem item = new GroceryItem();
            item.setListId(listId);
            item.setId(UUID.randomUUID().toString().toUpperCase());
            
            String itemName = node.has("name") ? node.get("name").asText() : "Unknown Item";
            int quantity = node.has("quantity") ? node.get("quantity").asInt(1) : 1;
            
            item.setName(itemName);
            item.setQuantity(quantity);
            item.setChecked(false);
            item.setPrice(0.0);
            item.setStore("");
    
            // Check if the node has notes and set them if available
            if (node.has("notes")) {
                item.setNotes(node.get("notes").asText());
            } else {
                item.setNotes("");
            }
            
            items.add(item);
        }
        
    
        // Create a new grocery list with all items included
        GroceryList list = new GroceryList();
        list.setId(listId);
        list.setUsername(username);
        list.setName(mealName);
        list.setItems(items);  // Set all items before saving
        list.setAI(true);
        
        // Set timestamps
        String currentTimestamp = String.valueOf(System.currentTimeMillis());
        list.setCreatedAt(currentTimestamp);
        list.setUpdatedAt(currentTimestamp);
    
        // Save the complete list with all items
        String savedListId;
        try {
            savedListId = createGroceryList(list, username);
        } catch (Exception e) {
            throw e;
        }

        // trophy for creating meals from ai
        userProfileService.incrementTrophy(username, "meal-prepper", 1);
    
        return savedListId;
    }
}
