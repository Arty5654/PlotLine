package com.plotline.backend.controller;

import com.plotline.backend.costs.CostsWriter;
import com.plotline.backend.plaid.TokenStore;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/costs")
public class CostsAssignController {
  private final CostsWriter costsWriter;
  private final TokenStore tokenStore;

  public CostsAssignController(CostsWriter w, TokenStore t) {
    this.costsWriter = w;
    this.tokenStore = t;
  }

  public record Assignment(String txnId, String date, String category, Double amount) {}
  public record AssignBody(String username, List<Assignment> assignments) {}

  @PostMapping("/assign")
  public ResponseEntity<?> assign(@RequestBody AssignBody body) {
    try {
      // aggregate by day -> category -> sum(amount)
      Map<String, Map<String, Double>> dayMap = new LinkedHashMap<>();
      for (Assignment a : body.assignments()) {
        if (a.amount() == null || a.amount() == 0.0) continue;
        var cats = dayMap.computeIfAbsent(a.date(), d -> new LinkedHashMap<>());
        cats.put(a.category(), round2(cats.getOrDefault(a.category(), 0.0) + a.amount()));
      }

      // write to weekly & monthly per day
      for (var e : dayMap.entrySet()) {
        costsWriter.mergeDated(body.username(), "weekly",  e.getKey(), e.getValue());
        costsWriter.mergeDated(body.username(), "monthly", e.getKey(), e.getValue());
      }

      return ResponseEntity.ok(Map.of("ok", true, "days", dayMap.keySet()));
    } catch (Exception ex) {
      ex.printStackTrace();
      return ResponseEntity.status(500).body(Map.of("error", ex.getMessage()));
    }
  }

  private static double round2(double v) { return Math.round(v * 100.0) / 100.0; }
}
