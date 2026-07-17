package com.plotline.backend.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.GroceryItem;
import com.plotline.backend.dto.GroceryList;
import com.plotline.backend.dto.GroceryListInvite;
import com.plotline.backend.service.DietaryRestrictionsService;
import com.plotline.backend.service.GroceryListService;
import com.plotline.backend.service.OpenAIService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.io.IOException;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * HTTP-layer tests for the grocery REST endpoints: routing, request/response mapping,
 * and status codes. The service is mocked, so this focuses purely on the controller.
 * The API-key filter is disabled (addFilters = false) since it isn't grocery-specific.
 */
@WebMvcTest(controllers = GroceryListController.class)
@AutoConfigureMockMvc(addFilters = false)
class GroceryListControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private GroceryListService groceryListService;

    @MockBean
    private OpenAIService openAIService;

    @MockBean
    private DietaryRestrictionsService dietaryRestrictionsService;

    private GroceryList sampleList(String id, String name, String owner) {
        GroceryList list = new GroceryList();
        list.setId(id);
        list.setName(name);
        list.setUsername(owner);
        list.setItems(List.of());
        return list;
    }

    private GroceryItem sampleItem(String id, String name) {
        GroceryItem it = new GroceryItem();
        it.setId(id);
        it.setName(name);
        it.setQuantity(1);
        return it;
    }

    // ── Create ──────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("POST /create-grocery-list returns the new id on success")
    void createList_success() throws Exception {
        when(groceryListService.createGroceryList(any(), anyString())).thenReturn("NEWID");

        mockMvc.perform(post("/api/groceryLists/create-grocery-list")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleList(null, "Weekly", "alice"))))
                .andExpect(status().isOk())
                .andExpect(content().string("NEWID"));
    }

    @Test
    @DisplayName("POST /create-grocery-list maps IllegalArgumentException to 400")
    void createList_badRequest() throws Exception {
        when(groceryListService.createGroceryList(any(), anyString()))
                .thenThrow(new IllegalArgumentException("A grocery list with this name already exists."));

        mockMvc.perform(post("/api/groceryLists/create-grocery-list")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleList(null, "Weekly", "alice"))))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("already exists")));
    }

    @Test
    @DisplayName("POST /create-grocery-list maps IOException to 500")
    void createList_serverError() throws Exception {
        when(groceryListService.createGroceryList(any(), anyString()))
                .thenThrow(new IOException("s3 down"));

        mockMvc.perform(post("/api/groceryLists/create-grocery-list")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleList(null, "Weekly", "alice"))))
                .andExpect(status().isInternalServerError());
    }

    // ── Reads ───────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("GET /get-grocery-lists/{username} returns the user's lists")
    void getLists() throws Exception {
        when(groceryListService.getGroceryListsForUser("alice"))
                .thenReturn(List.of(sampleList("L1", "Weekly", "alice")));

        mockMvc.perform(get("/api/groceryLists/get-grocery-lists/alice"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("Weekly"));
    }

    @Test
    @DisplayName("GET /{listId}/items returns the list's items")
    void getItems() throws Exception {
        when(groceryListService.getItems("alice", "L1"))
                .thenReturn(List.of(sampleItem("I1", "Milk")));

        mockMvc.perform(get("/api/groceryLists/L1/items").param("username", "alice"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("Milk"));
    }

    @Test
    @DisplayName("GET /{listId}/details returns 200 with the list when found")
    void getDetails_found() throws Exception {
        when(groceryListService.getGroceryList("alice", "L1"))
                .thenReturn(sampleList("L1", "Weekly", "alice"));

        mockMvc.perform(get("/api/groceryLists/L1/details").param("username", "alice"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Weekly"));
    }

    @Test
    @DisplayName("GET /{listId}/details returns 404 when the list is gone")
    void getDetails_notFound() throws Exception {
        when(groceryListService.getGroceryList("alice", "L1")).thenReturn(null);

        mockMvc.perform(get("/api/groceryLists/L1/details").param("username", "alice"))
                .andExpect(status().isNotFound());
    }

    // ── Item mutations ──────────────────────────────────────────────────────────

    @Test
    @DisplayName("POST /{listId}/items returns 200 on success and 400 on failure")
    void addItem() throws Exception {
        when(groceryListService.addItem(eq("alice"), eq("L1"), any())).thenReturn(true);
        mockMvc.perform(post("/api/groceryLists/L1/items").param("username", "alice")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleItem("I1", "Milk"))))
                .andExpect(status().isOk());

        when(groceryListService.addItem(eq("alice"), eq("L1"), any())).thenReturn(false);
        mockMvc.perform(post("/api/groceryLists/L1/items").param("username", "alice")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleItem("I1", "Milk"))))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("PATCH /{listId}/items/{itemId}/toggle returns 200 on success and 400 on failure")
    void toggleItem() throws Exception {
        when(groceryListService.toggleChecked("alice", "L1", "I1")).thenReturn(true);
        mockMvc.perform(patch("/api/groceryLists/L1/items/I1/toggle").param("username", "alice"))
                .andExpect(status().isOk());

        when(groceryListService.toggleChecked("alice", "L1", "I1")).thenReturn(false);
        mockMvc.perform(patch("/api/groceryLists/L1/items/I1/toggle").param("username", "alice"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("DELETE /{listId}/items/{itemId} returns 200 on success and 400 on failure")
    void deleteItem() throws Exception {
        when(groceryListService.deleteItem("alice", "L1", "I1")).thenReturn(true);
        mockMvc.perform(delete("/api/groceryLists/L1/items/I1").param("username", "alice"))
                .andExpect(status().isOk());

        when(groceryListService.deleteItem("alice", "L1", "I1")).thenReturn(false);
        mockMvc.perform(delete("/api/groceryLists/L1/items/I1").param("username", "alice"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("PUT /{listId}/items/{itemId} returns 200 on success and 400 on failure")
    void updateItem() throws Exception {
        when(groceryListService.updateItemDetails(eq("alice"), eq("L1"), any())).thenReturn(true);
        mockMvc.perform(put("/api/groceryLists/L1/items/I1").param("username", "alice")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleItem("I1", "Milk"))))
                .andExpect(status().isOk());

        when(groceryListService.updateItemDetails(eq("alice"), eq("L1"), any())).thenReturn(false);
        mockMvc.perform(put("/api/groceryLists/L1/items/I1").param("username", "alice")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleItem("I1", "Milk"))))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("DELETE /{listId} returns 200 on success and 500 on failure")
    void deleteList() throws Exception {
        when(groceryListService.deleteGroceryList("alice", "L1")).thenReturn(true);
        mockMvc.perform(delete("/api/groceryLists/L1").param("username", "alice"))
                .andExpect(status().isOk());

        when(groceryListService.deleteGroceryList("alice", "L1")).thenReturn(false);
        mockMvc.perform(delete("/api/groceryLists/L1").param("username", "alice"))
                .andExpect(status().isInternalServerError());
    }

    // ── Archive / restore ───────────────────────────────────────────────────────

    @Test
    @DisplayName("POST /archive/{username} returns 400 when the list has no id")
    void archive_requiresId() throws Exception {
        mockMvc.perform(post("/api/groceryLists/archive/alice")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleList(null, "Weekly", "alice"))))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("POST /archive/{username} returns 200 on success")
    void archive_success() throws Exception {
        when(groceryListService.archiveGroceryList(any(), eq("alice"))).thenReturn("archived/key");
        mockMvc.perform(post("/api/groceryLists/archive/alice")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleList("L1", "Weekly", "alice"))))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("GET /archived/{username} returns archived lists")
    void getArchived() throws Exception {
        when(groceryListService.getArchivedGroceryLists("alice"))
                .thenReturn(List.of(sampleList("L1", "Old", "alice")));
        mockMvc.perform(get("/api/groceryLists/archived/alice"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("Old"));
    }

    @Test
    @DisplayName("DELETE /archived/{username}/{listId} and DELETE /archived/{username} return 200")
    void deleteArchived() throws Exception {
        mockMvc.perform(delete("/api/groceryLists/archived/alice/L1"))
                .andExpect(status().isOk());
        mockMvc.perform(delete("/api/groceryLists/archived/alice"))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("POST /restore/{username} returns 400 without an id, 200 with one")
    void restore() throws Exception {
        mockMvc.perform(post("/api/groceryLists/restore/alice")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleList(null, "X", "alice"))))
                .andExpect(status().isBadRequest());

        when(groceryListService.restoreArchivedGroceryList(any(), eq("alice"))).thenReturn("lists/key");
        mockMvc.perform(post("/api/groceryLists/restore/alice")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleList("L1", "X", "alice"))))
                .andExpect(status().isOk());
    }

    // ── Sharing ─────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("POST /share returns the invite on success")
    void share_success() throws Exception {
        GroceryListInvite invite = new GroceryListInvite();
        invite.setId("INV1");
        invite.setListId("L1");
        when(groceryListService.shareGroceryList("alice", "bob", "L1")).thenReturn(invite);

        mockMvc.perform(post("/api/groceryLists/share")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fromUsername\":\"alice\",\"toUsername\":\"bob\",\"listId\":\"L1\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value("INV1"));
    }

    @Test
    @DisplayName("POST /share maps IllegalArgumentException (e.g. non-owner) to 400")
    void share_ownerOnlyRejected() throws Exception {
        when(groceryListService.shareGroceryList("bob", "carol", "L1"))
                .thenThrow(new IllegalArgumentException("Only the list owner can share this list."));

        mockMvc.perform(post("/api/groceryLists/share")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fromUsername\":\"bob\",\"toUsername\":\"carol\",\"listId\":\"L1\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("owner")));
    }

    @Test
    @DisplayName("POST /share returns 400 when required fields are missing")
    void share_missingFields() throws Exception {
        mockMvc.perform(post("/api/groceryLists/share")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fromUsername\":\"alice\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("GET /share/pending returns pending invites")
    void pendingInvites() throws Exception {
        GroceryListInvite invite = new GroceryListInvite();
        invite.setId("INV1");
        invite.setListName("Weekly");
        when(groceryListService.getPendingGroceryInvites("bob")).thenReturn(List.of(invite));

        mockMvc.perform(get("/api/groceryLists/share/pending").param("username", "bob"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value("INV1"));
    }

    @Test
    @DisplayName("POST /share/respond returns 200 on success and 400 when fields are missing")
    void respondToShare() throws Exception {
        mockMvc.perform(post("/api/groceryLists/share/respond")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"recipientUsername\":\"bob\",\"inviteId\":\"INV1\",\"accept\":\"true\"}"))
                .andExpect(status().isOk());

        mockMvc.perform(post("/api/groceryLists/share/respond")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"recipientUsername\":\"bob\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("POST /unshare returns 200 for the owner and 400 for a non-owner")
    void unshare() throws Exception {
        when(groceryListService.unshareGroceryList("alice", "L1", "bob")).thenReturn(true);
        mockMvc.perform(post("/api/groceryLists/unshare")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"ownerUsername\":\"alice\",\"listId\":\"L1\",\"memberUsername\":\"bob\"}"))
                .andExpect(status().isOk());

        when(groceryListService.unshareGroceryList("bob", "L1", "carol")).thenReturn(false);
        mockMvc.perform(post("/api/groceryLists/unshare")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"ownerUsername\":\"bob\",\"listId\":\"L1\",\"memberUsername\":\"carol\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("POST /unshare returns 400 when required fields are missing")
    void unshare_missingFields() throws Exception {
        mockMvc.perform(post("/api/groceryLists/unshare")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"ownerUsername\":\"alice\"}"))
                .andExpect(status().isBadRequest());
    }
}
