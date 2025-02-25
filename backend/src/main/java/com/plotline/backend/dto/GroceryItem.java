package com.plotline.backend.dto;

public class GroceryItem {
    private String listId;                  // ID of the list the item belongs to
    private String id;                      // Unique ID for the item
    private String name;                    // Name of the item
    private int quantity = 1;               // Quantity of the item
    private boolean isChecked = false;      // Whether the item is checked off
    private double price = 0.0;             // Price of the item
    private String store = "";              // Store where the item is available
    private String notes = "";              // Notes about the item

    // Default constructor
    public GroceryItem() {}

    // Getters and Setters
    public String getListId() {
        return listId;
    }

    public void setListId(String listId) {
        this.listId = listId;
    }

    public String getId() {
        return id;
    }

    public void setId(String itemID) {
        this.id = itemID;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public int getQuantity() {
        return quantity;
    }

    public void setQuantity(int quantity) {
        this.quantity = quantity;
    }

    public boolean isChecked() {
        return isChecked;
    }

    public void setChecked(boolean checked) {
        isChecked = checked;
    }

    public double getPrice() {
        return price;
    }

    public void setPrice(double price) {
        this.price = price;
    }

    public String getStore() {
        return store;
    }

    public void setStore(String store) {
        this.store = store;
    }

    public String getNotes() {
        return notes;
    }

    public void setNotes(String notes) {
        this.notes = notes;
    }
}
