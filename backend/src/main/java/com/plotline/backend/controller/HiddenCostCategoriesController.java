package com.plotline.backend.controller;

import static com.plotline.backend.util.UsernameUtils.normalize;

import java.io.ByteArrayInputStream;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.service.S3Service;

/**
 * Monthly Costs lists every budget category; the ones someone removed there are hidden from then on
 * (they stay in the budget). One small list per person: users/<name>/costs-hidden.json.
 */
@RestController
public class HiddenCostCategoriesController {

    static final int MAX_CATEGORIES = 200;

    private final S3Service s3;
    private final ObjectMapper json = new ObjectMapper();

    public HiddenCostCategoriesController(S3Service s3) {
        this.s3 = s3;
    }

    private static String key(String username) {
        return "users/" + normalize(username) + "/costs-hidden.json";
    }

    @GetMapping("/api/costs/hidden/{username}")
    public Map<String, List<String>> get(@PathVariable String username) {
        try {
            JsonNode saved = json.readTree(s3.downloadFile(key(username)));
            List<String> hidden = new ArrayList<>();
            saved.path("hidden").forEach(n -> hidden.add(n.asText()));
            return Map.of("hidden", hidden);
        } catch (Exception e) {
            return Map.of("hidden", List.of()); // nothing hidden yet
        }
    }

    @PutMapping("/api/costs/hidden/{username}")
    public ResponseEntity<?> put(@PathVariable String username, @RequestBody JsonNode body) throws Exception {
        if (body == null || !body.path("hidden").isArray()) return ResponseEntity.badRequest().body("Expected {\"hidden\": [...]}");
        LinkedHashSet<String> hidden = new LinkedHashSet<>();
        body.path("hidden").forEach(n -> { String c = n.asText("").strip(); if (!c.isEmpty() && c.length() <= 60) hidden.add(c); });
        if (hidden.size() > MAX_CATEGORIES) return ResponseEntity.badRequest().body("Too many categories");
        Map<String, List<String>> out = Map.of("hidden", new ArrayList<>(hidden));
        byte[] bytes = json.writeValueAsBytes(out);
        try (var in = new ByteArrayInputStream(bytes)) {
            s3.uploadFile(key(username), in, bytes.length);
        }
        return ResponseEntity.ok(out);
    }
}
