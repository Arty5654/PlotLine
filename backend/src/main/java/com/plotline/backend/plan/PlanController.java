package com.plotline.backend.plan;

import static com.plotline.backend.util.UsernameUtils.normalize;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.service.S3Service;

/**
 * Budget → Plan: savings goals, the emergency fund, debts for the payoff planner, and things owned
 * for net worth. One document per person (users/<name>/plan.json); the app does the math.
 */
@RestController
@RequestMapping("/api/plan")
public class PlanController {

    static final int MAX_BYTES = 200_000;

    private final S3Service s3;
    private final ObjectMapper json = new ObjectMapper();

    public PlanController(S3Service s3) {
        this.s3 = s3;
    }

    private static String key(String username) {
        return "users/" + normalize(username) + "/plan.json";
    }

    @GetMapping("/{username}")
    public ResponseEntity<JsonNode> get(@PathVariable String username) {
        try {
            return ResponseEntity.ok(json.readTree(s3.downloadFile(key(username))));
        } catch (Exception e) {
            return ResponseEntity.ok(json.createObjectNode()); // nothing planned yet
        }
    }

    @PutMapping("/{username}")
    public ResponseEntity<?> put(@PathVariable String username, @RequestBody JsonNode plan) throws Exception {
        if (plan == null || !plan.isObject()) return ResponseEntity.badRequest().body("Expected an object");
        byte[] bytes = json.writeValueAsBytes(plan);
        if (bytes.length > MAX_BYTES) return ResponseEntity.badRequest().body("That plan is too large");
        try (var in = new ByteArrayInputStream(bytes)) {
            s3.uploadFile(key(username), in, bytes.length);
        }
        return ResponseEntity.ok(plan);
    }

    static String text(byte[] bytes) {
        return new String(bytes, StandardCharsets.UTF_8);
    }
}
