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
            if (stored == null) {
                SubscriptionStatus offer = defaultOffer(username);
                writeStatus(username, offer);
                return ResponseEntity.ok(offer);
            }
            SubscriptionStatus effective = rollForward(stored);
            writeStatus(username, effective);
            return ResponseEntity.ok(effective);
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
            LocalDate now = LocalDate.now();
            LocalDate trialEnd = now.plusDays(30);
            SubscriptionStatus newStatus = new SubscriptionStatus(
                    "trial",
                    5.0,
                    trialEnd.format(ISO),
                    true,
                    "Trial ends on " + trialEnd.format(ISO) + ", then $5/month",
                    current != null ? current.getGraceEndsAt() : null,
                    false
            );
            writeStatus(username, newStatus);
            return ResponseEntity.ok(newStatus);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to claim", "detail", e.getMessage()));
        }
    }

    @PostMapping("/cancel")
    public ResponseEntity<?> cancel(@RequestBody Map<String, String> body) {
        try {
            String username = authService.normalizeUsername(body.get("username"));
            if (username == null || username.isBlank()) {
                return ResponseEntity.badRequest().body(Map.of("error", "username required"));
            }
            SubscriptionStatus current = readStatus(username);
            if (current == null) current = defaultOffer(username);
            SubscriptionStatus cancelled = new SubscriptionStatus(
                    "cancelled",
                    current.getMonthlyPrice(),
                    current.getTrialEndsAt(),
                    false,
                    "Subscription cancelled. Access continues until the end of your period.",
                    current.getGraceEndsAt(),
                    true
            );
            writeStatus(username, cancelled);
            return ResponseEntity.ok(cancelled);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to cancel", "detail", e.getMessage()));
        }
    }

    private SubscriptionStatus defaultOffer(String username) throws Exception {
        boolean lifetime = isEarlyBird(username);
        if (lifetime) {
            return new SubscriptionStatus("lifetime", 0.0, null, false, "Lifetime member", null, false);
        }
        LocalDate graceEnd = LocalDate.now().plusDays(30);
        return new SubscriptionStatus("grace", 5.0, null, false, "Free access for 30 days, then start free trial.", graceEnd.format(ISO), false);
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

    private SubscriptionStatus rollForward(SubscriptionStatus status) {
        LocalDate today = LocalDate.now();
        try {
            // Lifetime stays lifetime
            if ("lifetime".equalsIgnoreCase(status.getPlan())) return status;
            // Cancelled stays cancelled
            if (status.isCancelled()) return status;

            // Grace handling
            if ("grace".equalsIgnoreCase(status.getPlan()) && status.getGraceEndsAt() != null) {
                LocalDate graceEnd = LocalDate.parse(status.getGraceEndsAt(), ISO);
                if (today.isAfter(graceEnd)) {
                    return new SubscriptionStatus(
                            "needs-trial",
                            5.0,
                            null,
                            false,
                            "Your free month ended. Start your 30-day free trial to keep using PlotLine.",
                            status.getGraceEndsAt(),
                            false
                    );
                }
                return status;
            }

            // Trial handling
            if ("trial".equalsIgnoreCase(status.getPlan()) && status.getTrialEndsAt() != null) {
                LocalDate trialEnd = LocalDate.parse(status.getTrialEndsAt(), ISO);
                if (today.isAfter(trialEnd)) {
                    return new SubscriptionStatus(
                            "expired",
                            5.0,
                            status.getTrialEndsAt(),
                            false,
                            "Your free trial ended. Subscribe for $5/month to continue.",
                            status.getGraceEndsAt(),
                            false
                    );
                }
                return status;
            }
            return status;
        } catch (Exception e) {
            return status;
        }
    }
}
