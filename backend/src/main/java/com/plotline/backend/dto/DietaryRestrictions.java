package com.plotline.backend.dto;

public class DietaryRestrictions {
    private String username;
    private boolean lactoseIntolerant = false;
    private boolean vegetarian = false;
    private boolean vegan = false;
    private boolean glutenFree = false;
    private boolean kosher = false;
    private boolean dairyFree = false;
    private boolean nutFree = false;

    // Default constructor
    public DietaryRestrictions() {}

    // Getters and Setters
    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public boolean isLactoseIntolerant() {
        return lactoseIntolerant;
    }

    public void setLactoseIntolerant(boolean lactoseIntolerant) {
        this.lactoseIntolerant = lactoseIntolerant;
    }

    public boolean isVegetarian() {
        return vegetarian;
    }

    public void setVegetarian(boolean vegetarian) {
        this.vegetarian = vegetarian;
    }

    public boolean isVegan() {
        return vegan;
    }

    public void setVegan(boolean vegan) {
        this.vegan = vegan;
    }

    public boolean isGlutenFree() {
        return glutenFree;
    }

    public void setGlutenFree(boolean glutenFree) {
        this.glutenFree = glutenFree;
    }

    public boolean isKosher() {
        return kosher;
    }

    public void setKosher(boolean kosher) {
        this.kosher = kosher;
    }

    public boolean isDairyFree() {
        return dairyFree;
    }

    public void setDairyFree(boolean dairyFree) {
        this.dairyFree = dairyFree;
    }

    public boolean isNutFree() {
        return nutFree;
    }

    public void setNutFree(boolean nutFree) {
        this.nutFree = nutFree;
    }
}
