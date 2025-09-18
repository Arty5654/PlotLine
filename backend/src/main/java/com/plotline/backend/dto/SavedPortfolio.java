package com.plotline.backend.dto;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonFormat;

public class SavedPortfolio {

    @JsonFormat(shape = JsonFormat.Shape.STRING)
    public enum AccountType {
        BROKERAGE,
        ROTH_IRA;

        // forgiving parser used by controller and/or DTO convenience setter
        public static AccountType fromString(String s) {
            if (s == null) return BROKERAGE;
            String v = s.trim().toUpperCase();
            switch (v) {
                case "ROTH_IRA": return ROTH_IRA;
                case "BROKERAGE":
                default: return BROKERAGE;
            }
        }
    }

    private String username;
    private String portfolio;           
    private String originalPortfolio;   
    private String riskTolerance;
    private AccountType account;

    // Constructors
    public SavedPortfolio() {}

    @JsonCreator
    public SavedPortfolio(
            @JsonProperty("username") String username,
            @JsonProperty("portfolio") String portfolio,
            @JsonProperty("riskTolerance") String riskTolerance,
            @JsonProperty("account") AccountType account) {
        this.username = username;
        this.portfolio = portfolio;
        this.riskTolerance = riskTolerance;
        this.account = account;
    }

    // Getters
    public String getUsername() {
        return username;
    }

    public String getPortfolio() {
        return portfolio;
    }

    public String getOriginalPortfolio() {
        return originalPortfolio;
    }

    public String getRiskTolerance() {
        return riskTolerance;
    }

    public AccountType getAccount() {
        return account;
    }

    // Setters
    public void setUsername(String username) {
        this.username = username;
    }

    public void setPortfolio(String portfolio) {
        this.portfolio = portfolio;
    }

    public void setOriginalPortfolio(String originalPortfolio) {
        this.originalPortfolio = originalPortfolio;
    }

    public void setRiskTolerance(String riskTolerance) {
        this.riskTolerance = riskTolerance;
    }

    public void setAccount(AccountType accountType) {
        this.account = account;
    }

    public void setAccount(String account) {
        this.account = AccountType.fromString(account);
    }

    // public enum AccountType {
    //     BROKERAGE,
    //     ROTH_IRA;

    //     public static AccountType fromString(String s) {
    //         if (s == null) return BROKERAGE;
    //         switch (s.trim().toUpperCase()) {
    //             case "ROTH_IRA": return ROTH_IRA;
    //             case "BROKERAGE":
    //             default: return BROKERAGE;
    //         }
    //     }
    // }   
}


