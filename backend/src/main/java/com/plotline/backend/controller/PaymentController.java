package com.plotline.backend.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.SubscriptionStatus;
import com.plotline.backend.service.AuthService;
import com.plotline.backend.service.S3Service;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/payments")
public class PaymentController {

    private final S3Service s3Service;
    private final AuthService authService;
    private final ObjectMapper mapper = new ObjectMapper();
    private static final DateTimeFormatter ISO = DateTimeFormatter.ISO_LOCAL_DATE;

    public PaymentController(S3Service s3Service, AuthService authService) {
        this.s3Service = s3Service;
        this.authService = authService;
    }

    private String subKey(String username) {
        return "users/%s/subscription.json".formatted(username);
    }

    @GetMapping("/status/{username}")
    public ResponseEntity<?> status(@PathVariable String username) {
        try {
            SubscriptionStatus stored = readStatus(username);
            if (stored != null) {
                return ResponseEntity.ok(stored);
            }
            SubscriptionStatus offer = defaultOffer(username);
            return ResponseEntity.ok(offer);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to load status", "detail", e.getMessage()));
        }
    }

    @PostMapping("/claim")
    public ResponseEntity<?> claim(@RequestBody Map<String, String> body) {
        try {
            String username = authService.normalizeUsername(body.get("username"));
            if (username == null || username.isBlank()) {
                return ResponseEntity.badRequest().body(Map.of("error", "username required"));
            }
            SubscriptionStatus current = readStatus(username);
            if (current != null && "lifetime".equalsIgnoreCase(current.getPlan())) {
                return ResponseEntity.ok(current);
            }
            SubscriptionStatus newStatus = defaultOffer(username);
            writeStatus(username, newStatus);
            return ResponseEntity.ok(newStatus);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to claim", "detail", e.getMessage()));
        }
    }

    private SubscriptionStatus defaultOffer(String username) throws Exception {
        boolean lifetime = isEarlyBird(username);
        if (lifetime) {
            return new SubscriptionStatus("lifetime", 0.0, null, false, "Lifetime member");
        }
        LocalDate trialEnd = LocalDate.now().plusDays(30);
        return new SubscriptionStatus("trial", 5.0, trialEnd.format(ISO), true, "30-day free trial, then $5/month");
    }

    private boolean isEarlyBird(String username) throws Exception {
        List<String> users = authService.getAllUsernames();
        int idx = 0;
        for (String u : users) {
            idx++;
            if (u.equalsIgnoreCase(username)) break;
        }
        return idx > 0 && idx <= 1000;
    }

    private SubscriptionStatus readStatus(String username) {
        try {
            byte[] bytes = s3Service.downloadFile(subKey(username));
            if (bytes == null || bytes.length == 0) return null;
            return mapper.readValue(bytes, SubscriptionStatus.class);
        } catch (Exception e) {
            return null;
        }
    }

    private void writeStatus(String username, SubscriptionStatus status) throws Exception {
        String json = mapper.writeValueAsString(status);
        ByteArrayInputStream in = new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8));
        s3Service.uploadFile(subKey(username), in, json.length());
    }
}
