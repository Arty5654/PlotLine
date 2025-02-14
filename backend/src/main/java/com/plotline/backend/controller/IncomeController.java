package com.plotline.backend.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.IncomeRentRequest;
import com.plotline.backend.service.S3Service;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;

@RestController
@RequestMapping("/api/income")
public class IncomeController {

    @Autowired
    private S3Service s3Service;

    //private final String BUCKET_NAME = "plotline-income-rent";

    @PostMapping
    public ResponseEntity<String> saveIncomeData(@RequestBody IncomeRentRequest request) {
        try {
            // Convert JSON object to String
            String jsonData = new ObjectMapper().writeValueAsString(request);
            
            // Convert String to InputStream
            ByteArrayInputStream inputStream = new ByteArrayInputStream(jsonData.getBytes(StandardCharsets.UTF_8));

            // Generate S3 key
            String key = "users/" + request.getUsername() + "/income.json";

            // Upload file using S3Service
            s3Service.uploadFile(key, inputStream, jsonData.length());

            return ResponseEntity.ok("Income & Rent data saved successfully.");
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error saving data: " + e.getMessage());
        }
    }
}
