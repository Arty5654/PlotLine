package com.plotline.backend.dto;

import java.util.List;

public class GroceryListInvite {
    private String id;
    private String fromUsername;
    private String toUsername;
    private String ownerUsername;   // Owner of the canonical list (may differ from fromUsername on re-share)
    private String listId;
    private String listName;
    private String sentAt;
    private List<GroceryItem> items;

    public GroceryListInvite() {}

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getFromUsername() { return fromUsername; }
    public void setFromUsername(String fromUsername) { this.fromUsername = fromUsername; }

    public String getToUsername() { return toUsername; }
    public void setToUsername(String toUsername) { this.toUsername = toUsername; }

    public String getOwnerUsername() { return ownerUsername; }
    public void setOwnerUsername(String ownerUsername) { this.ownerUsername = ownerUsername; }

    public String getListId() { return listId; }
    public void setListId(String listId) { this.listId = listId; }

    public String getListName() { return listName; }
    public void setListName(String listName) { this.listName = listName; }

    public String getSentAt() { return sentAt; }
    public void setSentAt(String sentAt) { this.sentAt = sentAt; }

    public List<GroceryItem> getItems() { return items; }
    public void setItems(List<GroceryItem> items) { this.items = items; }
}
