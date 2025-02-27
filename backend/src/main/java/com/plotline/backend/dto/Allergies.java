package com.plotline.backend.dto;

import java.util.ArrayList;
import java.util.List;

public class Allergies  {
    private String username;  // Unique identifier for the allergy preferences
    private List<String> allergies = new ArrayList<>();  // List of allergies (each allergy represented by a string)

    // Default constructor
    public Allergies() {}

    // Constructor with a list of allergies
    public Allergies(String username, List<String> allergies) {
        this.username = username;
        this.allergies = allergies;
    }

    // Getters and Setters
    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public List<String> getAllergies() {
        return allergies;
    }

    public void setAllergies(List<String> allergies) {
        this.allergies = allergies;
    }
}
