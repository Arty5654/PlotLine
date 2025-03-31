package com.plotline.backend.dto;

public class WatchlistEntry {
    private String username;
    private String symbol;

    public WatchlistEntry() {}

    public WatchlistEntry(String username, String symbol) {
        this.username = username;
        this.symbol = symbol;
    }

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public String getSymbol() { return symbol; }
    public void setSymbol(String symbol) { this.symbol = symbol; }
}
