package com.plotline.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.SavedPortfolio;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;

@Service
public class PortfolioService {
    @Autowired
    private S3Service s3Service;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private String getOriginalKey(String username) {
        return "users/" + username + "/original-portfolio.json";
    }
    
    private String getEditedKey(String username) {
        return "users/" + username + "/edited-portfolio.json";
    }
    
    public void saveOriginalPortfolio(String username, SavedPortfolio portfolio) {
        saveToS3(getOriginalKey(username), portfolio);
    }
    
    public void saveEditedPortfolio(String username, SavedPortfolio portfolio) {
        saveToS3(getEditedKey(username), portfolio);
    }
    
    public SavedPortfolio loadOriginalPortfolio(String username) {
        return loadFromS3(getOriginalKey(username));
    }
    
    public SavedPortfolio loadEditedPortfolio(String username) {
        return loadFromS3(getEditedKey(username));
    }
    
    private void saveToS3(String key, SavedPortfolio portfolio) {
        try {
            String json = objectMapper.writeValueAsString(portfolio);
            byte[] jsonBytes = json.getBytes(StandardCharsets.UTF_8);
            ByteArrayInputStream stream = new ByteArrayInputStream(jsonBytes);
            s3Service.uploadFile(key, stream, jsonBytes.length);
        } catch (Exception e) {
            throw new RuntimeException("Failed to save portfolio", e);
        }
    }
    
    
    private SavedPortfolio loadFromS3(String key) {
        try {
            byte[] data = s3Service.downloadFile(key);
            if (data == null || data.length == 0) {
                System.out.println("Empty file or data for key: " + key);
                return null;
            }
            String json = new String(data, StandardCharsets.UTF_8);
            return objectMapper.readValue(json, SavedPortfolio.class);
        } catch (Exception e) {
            System.out.println("Could not load from " + key + ": " + e.getMessage());
            return null;
        }
    }
    

    public void deleteEditedPortfolio(String username) {
        try {
            s3Service.deleteFile(getEditedKey(username));
            System.out.println("Deleted edited portfolio for: " + username);
        } catch (Exception e) {
            System.out.println("⚠️ Failed to delete edited portfolio: " + e.getMessage());
        }
    }    
}    