package com.plotline.backend.service;

import com.plotline.backend.dto.GroceryItem;
import com.plotline.backend.dto.GroceryList;
import com.plotline.backend.dto.GroceryListInvite;
import com.plotline.backend.dto.Trophy;
import com.plotline.backend.testsupport.InMemoryS3Client;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import java.util.Collections;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Hermetic integration tests for the grocery feature. The service runs against an
 * in-memory S3 double, so no AWS credentials, API keys, or deployed backend are needed.
 */
class GroceryListServiceTest {

    private InMemoryS3Client s3;
    private GroceryListService service;

    /** No-op UserProfileService stub so trophy hooks don't touch storage (avoids Mockito). */
    private static class NoOpUserProfileService extends UserProfileService {
        NoOpUserProfileService(InMemoryS3Client s3) {
            super(s3, null);
        }
        @Override
        public java.util.List<Trophy> incrementTrophy(String username, String trophyId, int amount) {
            return Collections.emptyList();
        }
    }

    @BeforeEach
    void setUp() {
        s3 = new InMemoryS3Client();
        service = new GroceryListService(s3, new NoOpUserProfileService(s3));
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private String createList(String user, String name) throws Exception {
        GroceryList list = new GroceryList();
        list.setName(name);
        list.setUsername(user);
        list.setItems(new ArrayList<>());
        return service.createGroceryList(list, user);
    }

    private GroceryItem item(String id, String name) {
        GroceryItem it = new GroceryItem();
        it.setId(id);
        it.setName(name);
        it.setQuantity(1);
        it.setChecked(false);
        return it;
    }

    private List<String> itemNames(String user, String listId) {
        List<GroceryItem> items = service.getItems(user, listId);
        List<String> names = new ArrayList<>();
        for (GroceryItem it : items) names.add(it.getName());
        return names;
    }

    private GroceryItem findItem(String user, String listId, String itemId) {
        return service.getItems(user, listId).stream()
                .filter(i -> i.getId().equals(itemId))
                .findFirst().orElse(null);
    }

    /** Overwrite the stored canonical list (used to set up an aged createdAt). */
    private void writeListDirect(String user, GroceryList list) throws Exception {
        String key = "users/" + user + "/grocery/lists/" + list.getId() + ".json";
        byte[] json = new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsBytes(list);
        s3.putRaw(key, json);
    }

    private String isoDaysAgo(int days) {
        java.text.SimpleDateFormat iso = new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
        iso.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
        return iso.format(new java.util.Date(System.currentTimeMillis() - days * 24L * 60 * 60 * 1000));
    }

    // ── Create / basic item ops ─────────────────────────────────────────────────

    @Test
    @DisplayName("createGroceryList stores an owned list with no members")
    void createGroceryList_setsOwnerAndEmptyMembers() throws Exception {
        String listId = createList("alice", "Weekly");

        GroceryList stored = service.getGroceryList("alice", listId);
        assertThat(stored).isNotNull();
        assertThat(stored.getName()).isEqualTo("Weekly");
        assertThat(stored.getOwnerUsername()).isEqualTo("alice");
        assertThat(stored.getMembers()).isEmpty();
    }

    @Test
    @DisplayName("createGroceryList rejects a duplicate name for the same user")
    void createGroceryList_rejectsDuplicateName() throws Exception {
        createList("alice", "Weekly");
        assertThatThrownBy(() -> createList("alice", "Weekly"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("already exists");
    }

    @Test
    @DisplayName("createGroceryList enforces the 10 active-list limit")
    void createGroceryList_enforcesTenListLimit() throws Exception {
        for (int i = 0; i < 10; i++) createList("alice", "List " + i);
        assertThatThrownBy(() -> createList("alice", "List 11"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("limit of 10");
    }

    @Test
    @DisplayName("addItem and deleteItem update the list")
    void addAndDeleteItem() throws Exception {
        String listId = createList("alice", "Groceries");

        assertThat(service.addItem("alice", listId, item("I1", "Milk"))).isTrue();
        assertThat(service.addItem("alice", listId, item("I2", "Eggs"))).isTrue();
        assertThat(itemNames("alice", listId)).containsExactly("Milk", "Eggs");

        assertThat(service.deleteItem("alice", listId, "I1")).isTrue();
        assertThat(itemNames("alice", listId)).containsExactly("Eggs");
    }

    @Test
    @DisplayName("updateItemDetails changes fields but preserves who checked it")
    void updateItemDetails_preservesCheckedBy() throws Exception {
        String listId = createList("alice", "Groceries");
        service.addItem("alice", listId, item("I1", "Milk"));
        service.toggleChecked("alice", listId, "I1");

        GroceryItem edit = item("I1", "Whole Milk");
        edit.setQuantity(3);
        edit.setChecked(true);
        assertThat(service.updateItemDetails("alice", listId, edit)).isTrue();

        GroceryItem updated = findItem("alice", listId, "I1");
        assertThat(updated.getName()).isEqualTo("Whole Milk");
        assertThat(updated.getQuantity()).isEqualTo(3);
        assertThat(updated.getCheckedBy()).isEqualTo("alice"); // attribution preserved
    }

    // ── "Who got it" attribution ────────────────────────────────────────────────

    @Test
    @DisplayName("toggleChecked records who checked the item and clears it on uncheck")
    void toggleChecked_recordsCheckedBy() throws Exception {
        String listId = createList("alice", "Groceries");
        service.addItem("alice", listId, item("I1", "Milk"));

        service.toggleChecked("alice", listId, "I1");
        GroceryItem checked = findItem("alice", listId, "I1");
        assertThat(checked.isChecked()).isTrue();
        assertThat(checked.getCheckedBy()).isEqualTo("alice");

        service.toggleChecked("alice", listId, "I1");
        GroceryItem unchecked = findItem("alice", listId, "I1");
        assertThat(unchecked.isChecked()).isFalse();
        assertThat(unchecked.getCheckedBy()).isNull();
    }

    // ── Sharing + real-time sync ────────────────────────────────────────────────

    @Test
    @DisplayName("accepting a share joins the owner's canonical list (member sees it)")
    void acceptShare_joinsCanonicalList() throws Exception {
        String listId = createList("alice", "Groceries");
        service.addItem("alice", listId, item("I1", "Milk"));

        GroceryListInvite invite = service.shareGroceryList("alice", "bob", listId);
        service.respondToGroceryShare("bob", invite.getId(), true);

        // Bob sees the shared list and its items
        assertThat(service.getGroceryListsForUser("bob"))
                .anyMatch(l -> l.getId().equals(listId));
        assertThat(itemNames("bob", listId)).contains("Milk");

        // The canonical list records bob as a member
        assertThat(service.getGroceryList("alice", listId).getMembers()).contains("bob");
    }

    @Test
    @DisplayName("owner's item edits sync to a member's view (the shared-list sync bug)")
    void ownerEdits_syncToMember() throws Exception {
        String listId = createList("alice", "Groceries");
        service.addItem("alice", listId, item("I1", "Milk"));
        GroceryListInvite invite = service.shareGroceryList("alice", "bob", listId);
        service.respondToGroceryShare("bob", invite.getId(), true);

        // Owner adds an item AFTER sharing — member must see it
        service.addItem("alice", listId, item("I2", "Eggs"));
        assertThat(itemNames("bob", listId)).contains("Milk", "Eggs");
    }

    @Test
    @DisplayName("a member's check syncs back to the owner with attribution")
    void memberCheck_syncsToOwnerWithAttribution() throws Exception {
        String listId = createList("alice", "Groceries");
        service.addItem("alice", listId, item("I1", "Milk"));
        GroceryListInvite invite = service.shareGroceryList("alice", "bob", listId);
        service.respondToGroceryShare("bob", invite.getId(), true);

        service.toggleChecked("bob", listId, "I1");

        GroceryItem asSeenByOwner = findItem("alice", listId, "I1");
        assertThat(asSeenByOwner.isChecked()).isTrue();
        assertThat(asSeenByOwner.getCheckedBy()).isEqualTo("bob");
    }

    @Test
    @DisplayName("only the owner can share the list")
    void sharing_isOwnerOnly() throws Exception {
        String listId = createList("alice", "Groceries");
        GroceryListInvite invite = service.shareGroceryList("alice", "bob", listId);
        service.respondToGroceryShare("bob", invite.getId(), true);

        // Bob is a member, not the owner — he cannot re-share
        assertThatThrownBy(() -> service.shareGroceryList("bob", "carol", listId))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("owner");
    }

    @Test
    @DisplayName("unshare removes a member's access")
    void unshare_removesMemberAccess() throws Exception {
        String listId = createList("alice", "Groceries");
        GroceryListInvite invite = service.shareGroceryList("alice", "bob", listId);
        service.respondToGroceryShare("bob", invite.getId(), true);

        assertThat(service.unshareGroceryList("alice", listId, "bob")).isTrue();

        assertThat(service.getGroceryListsForUser("bob"))
                .noneMatch(l -> l.getId().equals(listId));
        assertThat(service.getGroceryList("alice", listId).getMembers()).doesNotContain("bob");
    }

    @Test
    @DisplayName("owner deleting a shared list removes it for members too")
    void ownerDelete_propagatesToMembers() throws Exception {
        String listId = createList("alice", "Groceries");
        GroceryListInvite invite = service.shareGroceryList("alice", "bob", listId);
        service.respondToGroceryShare("bob", invite.getId(), true);

        assertThat(service.deleteGroceryList("alice", listId)).isTrue();

        assertThat(service.getGroceryListsForUser("bob"))
                .noneMatch(l -> l.getId().equals(listId));
        assertThat(service.getGroceryList("bob", listId)).isNull();
    }

    @Test
    @DisplayName("a member leaving a shared list doesn't affect the owner")
    void memberLeave_keepsListForOwner() throws Exception {
        String listId = createList("alice", "Groceries");
        GroceryListInvite invite = service.shareGroceryList("alice", "bob", listId);
        service.respondToGroceryShare("bob", invite.getId(), true);

        // Bob "leaves" via delete on his side
        assertThat(service.deleteGroceryList("bob", listId)).isTrue();

        assertThat(service.getGroceryListsForUser("bob"))
                .noneMatch(l -> l.getId().equals(listId));
        assertThat(service.getGroceryListsForUser("alice"))
                .anyMatch(l -> l.getId().equals(listId));
        assertThat(service.getGroceryList("alice", listId).getMembers()).doesNotContain("bob");
    }

    // ── Archive / restore / auto-delete ─────────────────────────────────────────

    @Test
    @DisplayName("archive moves a list out of active and into archived")
    void archive_movesListToArchived() throws Exception {
        String listId = createList("alice", "Groceries");
        service.addItem("alice", listId, item("I1", "Milk"));

        service.archiveGroceryList(service.getGroceryList("alice", listId), "alice");

        assertThat(service.getGroceryListsForUser("alice"))
                .noneMatch(l -> l.getId().equals(listId));
        assertThat(service.getArchivedGroceryLists("alice"))
                .anyMatch(l -> l.getId().equals(listId));
    }

    @Test
    @DisplayName("restore returns a private list with items unchecked and members cleared")
    void restore_resetsSharedStateAndChecks() throws Exception {
        String listId = createList("alice", "Groceries");
        service.addItem("alice", listId, item("I1", "Milk"));
        service.toggleChecked("alice", listId, "I1");
        GroceryListInvite invite = service.shareGroceryList("alice", "bob", listId);
        service.respondToGroceryShare("bob", invite.getId(), true);

        service.archiveGroceryList(service.getGroceryList("alice", listId), "alice");
        GroceryList archived = service.getArchivedGroceryLists("alice").stream()
                .filter(l -> l.getId().equals(listId)).findFirst().orElseThrow();
        service.restoreArchivedGroceryList(archived, "alice");

        GroceryList restored = service.getGroceryList("alice", listId);
        assertThat(restored).isNotNull();
        assertThat(restored.getMembers()).isEmpty();
        assertThat(restored.getOwnerUsername()).isEqualTo("alice");
        assertThat(restored.getItems()).allMatch(i -> !i.isChecked());
        assertThat(restored.getItems()).allMatch(i -> i.getCheckedBy() == null);
    }

    @Test
    @DisplayName("archived lists older than 7 days are auto-deleted on fetch")
    void archived_autoDeletedAfterSevenDays() throws Exception {
        String listId = createList("alice", "Groceries");
        service.archiveGroceryList(service.getGroceryList("alice", listId), "alice");

        String archivedKey = "users/alice/grocery/archived/" + listId + ".json";
        assertThat(s3.contains(archivedKey)).isTrue();

        // Backdate the archive time to 8 days ago
        s3.setLastModified(archivedKey, Instant.now().minus(8, ChronoUnit.DAYS));

        assertThat(service.getArchivedGroceryLists("alice")).isEmpty();
        assertThat(s3.contains(archivedKey)).isFalse();
    }

    // ── Concurrency (per-list lock prevents lost updates) ───────────────────────

    @Test
    @DisplayName("concurrent toggles on one list don't lose updates")
    void concurrentToggles_noLostUpdates() throws Exception {
        String listId = createList("alice", "Groceries");
        int n = 25;
        for (int i = 0; i < n; i++) {
            service.addItem("alice", listId, item("C" + i, "item" + i));
        }

        ExecutorService pool = Executors.newFixedThreadPool(8);
        List<Future<?>> futures = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            final String itemId = "C" + i;
            futures.add(pool.submit(() -> service.toggleChecked("alice", listId, itemId)));
        }
        for (Future<?> f : futures) f.get();
        pool.shutdown();
        pool.awaitTermination(30, TimeUnit.SECONDS);

        List<GroceryItem> items = service.getItems("alice", listId);
        assertThat(items).hasSize(n);
        assertThat(items).allMatch(GroceryItem::isChecked);
    }

    // ── Additional coverage ─────────────────────────────────────────────────────

    @Test
    @DisplayName("declining a share adds no member and clears the invite")
    void declineShare_addsNoMember() throws Exception {
        String listId = createList("alice", "Groceries");
        GroceryListInvite invite = service.shareGroceryList("alice", "bob", listId);

        service.respondToGroceryShare("bob", invite.getId(), false);

        assertThat(service.getGroceryList("alice", listId).getMembers()).doesNotContain("bob");
        assertThat(service.getGroceryListsForUser("bob")).noneMatch(l -> l.getId().equals(listId));
        assertThat(service.getPendingGroceryInvites("bob")).isEmpty();
    }

    @Test
    @DisplayName("getPendingGroceryInvites returns invites sent to the user")
    void pendingInvites_areReturned() throws Exception {
        String listId = createList("alice", "Groceries");
        service.shareGroceryList("alice", "bob", listId);

        List<GroceryListInvite> invites = service.getPendingGroceryInvites("bob");
        assertThat(invites).hasSize(1);
        assertThat(invites.get(0).getListId()).isEqualTo(listId);
        assertThat(invites.get(0).getFromUsername()).isEqualToIgnoringCase("alice");
    }

    @Test
    @DisplayName("duplicate-name check is case-insensitive")
    void duplicateName_isCaseInsensitive() throws Exception {
        createList("alice", "Weekly");
        assertThatThrownBy(() -> createList("alice", "weekly"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("already exists");
    }

    @Test
    @DisplayName("lists older than 14 days are auto-archived on fetch")
    void oldList_isAutoArchived() throws Exception {
        String listId = createList("alice", "Groceries");

        // Age the list past the 14-day threshold
        GroceryList list = service.getGroceryList("alice", listId);
        list.setCreatedAt(isoDaysAgo(15));
        writeListDirect("alice", list);

        assertThat(service.getGroceryListsForUser("alice"))
                .noneMatch(l -> l.getId().equals(listId));
        assertThat(service.getArchivedGroceryLists("alice"))
                .anyMatch(l -> l.getId().equals(listId));
    }

    @Test
    @DisplayName("a shared list is never auto-archived (would strand members)")
    void sharedList_isNotAutoArchived() throws Exception {
        String listId = createList("alice", "Groceries");
        GroceryListInvite invite = service.shareGroceryList("alice", "bob", listId);
        service.respondToGroceryShare("bob", invite.getId(), true);

        // Age it past 14 days — but it's shared, so it must stay active
        GroceryList list = service.getGroceryList("alice", listId);
        list.setCreatedAt(isoDaysAgo(20));
        writeListDirect("alice", list);

        assertThat(service.getGroceryListsForUser("alice"))
                .anyMatch(l -> l.getId().equals(listId));
    }

    @Test
    @DisplayName("owner archiving a shared list removes it for members too")
    void ownerArchive_propagatesToMembers() throws Exception {
        String listId = createList("alice", "Groceries");
        GroceryListInvite invite = service.shareGroceryList("alice", "bob", listId);
        service.respondToGroceryShare("bob", invite.getId(), true);

        service.archiveGroceryList(service.getGroceryList("alice", listId), "alice");

        assertThat(service.getGroceryListsForUser("bob"))
                .noneMatch(l -> l.getId().equals(listId));
    }

    @Test
    @DisplayName("a member 'archiving' a shared list just leaves it (no snapshot)")
    void memberArchive_leavesWithoutSnapshot() throws Exception {
        String listId = createList("alice", "Groceries");
        GroceryListInvite invite = service.shareGroceryList("alice", "bob", listId);
        service.respondToGroceryShare("bob", invite.getId(), true);

        service.archiveGroceryList(service.getGroceryList("bob", listId), "bob");

        assertThat(service.getGroceryListsForUser("bob")).noneMatch(l -> l.getId().equals(listId));
        assertThat(service.getArchivedGroceryLists("bob")).isEmpty();       // no private snapshot
        assertThat(service.getGroceryListsForUser("alice")).anyMatch(l -> l.getId().equals(listId));
        assertThat(service.getGroceryList("alice", listId).getMembers()).doesNotContain("bob");
    }

    @Test
    @DisplayName("deleteArchivedGroceryList and deleteAllArchivedGroceryLists remove archived lists")
    void deleteArchived_removesArchivedLists() throws Exception {
        String a = createList("alice", "A");
        String b = createList("alice", "B");
        service.archiveGroceryList(service.getGroceryList("alice", a), "alice");
        service.archiveGroceryList(service.getGroceryList("alice", b), "alice");

        service.deleteArchivedGroceryList("alice", a);
        assertThat(service.getArchivedGroceryLists("alice")).noneMatch(l -> l.getId().equals(a));
        assertThat(service.getArchivedGroceryLists("alice")).anyMatch(l -> l.getId().equals(b));

        service.deleteAllArchivedGroceryLists("alice");
        assertThat(service.getArchivedGroceryLists("alice")).isEmpty();
    }

    @Test
    @DisplayName("a member's pointer to a deleted canonical list is pruned on fetch")
    void stalePointer_isPrunedOnFetch() throws Exception {
        String listId = createList("alice", "Groceries");
        GroceryListInvite invite = service.shareGroceryList("alice", "bob", listId);
        service.respondToGroceryShare("bob", invite.getId(), true);

        // Delete the canonical file directly, leaving bob's pointer dangling
        s3.deleteRaw("users/alice/grocery/lists/" + listId + ".json");

        assertThat(service.getGroceryListsForUser("bob")).noneMatch(l -> l.getId().equals(listId));
        assertThat(s3.contains("users/bob/grocery/shared/" + listId + ".json")).isFalse();
    }
}
