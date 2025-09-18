package com.plotline.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.SavedPortfolio;
import com.plotline.backend.dto.SavedPortfolio.AccountType;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;

@Service
public class PortfolioService {

    @Autowired
    private S3Service s3Service;

    private final ObjectMapper objectMapper = new ObjectMapper();

    // ---------- Key helpers (per account) ----------
    private String getOriginalKey(String username, AccountType acct) {
        // users/{u}/portfolio/{account}/original.json
        return "users/%s/portfolio/%s/original.json"
                .formatted(username, acct.name().toLowerCase());
    }

    private String getEditedKey(String username, AccountType acct) {
        // users/{u}/portfolio/{account}/edited.json
        return "users/%s/portfolio/%s/edited.json"
                .formatted(username, acct.name().toLowerCase());
    }

    // ---------- Save / Load (per account) ----------
    public void saveOriginalPortfolio(String username, AccountType acct, SavedPortfolio portfolio) {
        // ensure DTO has accountType set
        if (portfolio.getAccount() == null) portfolio.setAccount(acct);
        saveToS3(getOriginalKey(username, acct), portfolio);
    }

    public void saveEditedPortfolio(String username, AccountType acct, SavedPortfolio portfolio) {
        if (portfolio.getAccount() == null) portfolio.setAccount(acct);
        saveToS3(getEditedKey(username, acct), portfolio);
    }

    public SavedPortfolio loadOriginalPortfolio(String username, AccountType acct) {
        return loadFromS3(getOriginalKey(username, acct));
    }

    public SavedPortfolio loadEditedPortfolio(String username, AccountType acct) {
        return loadFromS3(getEditedKey(username, acct));
    }

    public void deleteOriginalPortfolio(String username, AccountType acct) {
        try {
            s3Service.deleteFile(getOriginalKey(username, acct));
            System.out.println("Deleted original portfolio for: " + username + " / " + acct);
        } catch (Exception e) {
            System.out.println("Failed to delete original portfolio: " + e.getMessage());
        }
    }

    public void deleteEditedPortfolio(String username, AccountType acct) {
        try {
            s3Service.deleteFile(getEditedKey(username, acct));
            System.out.println("Deleted edited portfolio for: " + username + " / " + acct);
        } catch (Exception e) {
            System.out.println("Failed to delete edited portfolio: " + e.getMessage());
        }
    }

    public void saveOriginalPortfolio(String username, SavedPortfolio portfolio) {
        saveOriginalPortfolio(username, AccountType.BROKERAGE, portfolio);
    }

    public void saveEditedPortfolio(String username, SavedPortfolio portfolio) {
        saveEditedPortfolio(username, AccountType.BROKERAGE, portfolio);
    }

    public SavedPortfolio loadOriginalPortfolio(String username) {
        return loadOriginalPortfolio(username, AccountType.BROKERAGE);
    }

    public SavedPortfolio loadEditedPortfolio(String username) {
        return loadEditedPortfolio(username, AccountType.BROKERAGE);
    }

    public void deleteOriginalPortfolio(String username) {
        deleteOriginalPortfolio(username, AccountType.BROKERAGE);
    }

    public void deleteEditedPortfolio(String username) {
        deleteEditedPortfolio(username, AccountType.BROKERAGE);
    }

    // ---------- S3 helpers ----------
    private void saveToS3(String key, SavedPortfolio portfolio) {
        try {
            String json = objectMapper.writeValueAsString(portfolio);
            byte[] jsonBytes = json.getBytes(StandardCharsets.UTF_8);
            try (ByteArrayInputStream stream = new ByteArrayInputStream(jsonBytes)) {
                // if uploadFile needs a long length, cast it
                s3Service.uploadFile(key, stream, (long) jsonBytes.length);
            }
        } catch (Exception e) {
            throw new RuntimeException("Failed to save portfolio to " + key, e);
        }
    }

    private SavedPortfolio loadFromS3(String key) {
        try {
            byte[] data = s3Service.downloadFile(key);
            if (data == null || data.length == 0) {
                System.out.println("Empty or missing file for key: " + key);
                return null;
            }
            String json = new String(data, StandardCharsets.UTF_8);
            return objectMapper.readValue(json, SavedPortfolio.class);
        } catch (Exception e) {
            System.out.println("Could not load from " + key + ": " + e.getMessage());
            return null;
        }
    }
}
