package com.plotline.backend.dto;

public class GroceryItem {
    private String id;                      // Unique ID for the item
    private String name;                    // Name of the item
    private int quantity = 1;               // Quantity of the item
    private boolean isChecked = false;      // Whether the item is checked off

    // Default constructor
    public GroceryItem() {}

    // Getters and Setters
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
}
