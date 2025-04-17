package com.plotline.backend.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.WatchlistEntry;
import com.plotline.backend.service.S3Service;
import com.plotline.backend.service.UserProfileService;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

@RestController
@RequestMapping("/api/watchlist")
public class WatchlistController {

    @Autowired
    private S3Service s3Service;

    @Autowired
    private UserProfileService userProfileService;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private String getKey(String username) {
        return "users/" + username + "/watchlist.json";
    }

    @PostMapping("/add")
    public ResponseEntity<String> addToWatchlist(@RequestBody WatchlistEntry entry) {
        try {
            List<String> watchlist = getWatchlist(entry.getUsername());
            if (!watchlist.contains(entry.getSymbol())) {
                watchlist.add(entry.getSymbol());
                saveWatchlist(entry.getUsername(), watchlist);

                // Increment trophy progress for adding to watchlist
                userProfileService.incrementTrophy(entry.getUsername(), "watchlist-adder", 1);

            }
            return ResponseEntity.ok("Added to watchlist.");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("Error adding to watchlist: " + e.getMessage());
        }
    }

    @PostMapping("/remove")
    public ResponseEntity<String> removeFromWatchlist(@RequestBody WatchlistEntry entry) {
        try {
            List<String> watchlist = getWatchlist(entry.getUsername());
            if (watchlist.remove(entry.getSymbol())) {
                saveWatchlist(entry.getUsername(), watchlist);
            }
            return ResponseEntity.ok("Removed from watchlist.");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("Error removing from watchlist: " + e.getMessage());
        }
    }

    @GetMapping("/{username}")
    public ResponseEntity<List<String>> getWatchlistForUser(@PathVariable String username) {
        try {
            List<String> watchlist = getWatchlist(username);
            return ResponseEntity.ok(watchlist);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(null);
        }
    }

    private List<String> getWatchlist(String username) {
        try {
            byte[] data = s3Service.downloadFile(getKey(username));
            return objectMapper.readValue(data, List.class);
        } catch (Exception e) {
            return new ArrayList<>(); // Return empty if not found
        }
    }

    private void saveWatchlist(String username, List<String> watchlist) throws IOException {
        byte[] json = objectMapper.writeValueAsBytes(watchlist);
        ByteArrayInputStream stream = new ByteArrayInputStream(json);
        s3Service.uploadFile(getKey(username), stream, json.length);
    }
}
