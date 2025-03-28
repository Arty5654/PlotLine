package com.plotline.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.SavedPortfolio;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;

@Service
public class PortfolioService {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final String S3_KEY_TEMPLATE = "users/%s/saved-portfolio.json";

    @Autowired
    private S3Service s3Service;

    public void savePortfolio(String username, SavedPortfolio portfolio) {
        try {
            String jsonData = objectMapper.writeValueAsString(portfolio);
            ByteArrayInputStream inputStream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));
            String key = String.format(S3_KEY_TEMPLATE, username);
            s3Service.uploadFile(key, inputStream, jsonData.length());
        } catch (Exception e) {
            throw new RuntimeException("Error saving portfolio to S3", e);
        }
    }

    public SavedPortfolio loadPortfolio(String username) {
        try {
            String key = String.format(S3_KEY_TEMPLATE, username);
            byte[] fileData = s3Service.downloadFile(key);
            String jsonData = new String(fileData, StandardCharsets.UTF_8);
            return objectMapper.readValue(jsonData, SavedPortfolio.class);
        } catch (Exception e) {
            System.out.println("Portfolio not found for user: " + username);
            return null;
        }
    }
}
