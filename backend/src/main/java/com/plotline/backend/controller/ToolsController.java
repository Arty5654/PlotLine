package com.plotline.backend.controller;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.plotline.backend.tax.TakeHomeCalculator;

/** Budget → Plan → First-job tools: the paycheck → take-home calculator (the same math as the budget quiz). */
@RestController
@RequestMapping("/api/tools")
public class ToolsController {

    private final TakeHomeCalculator takeHome;

    public ToolsController(TakeHomeCalculator takeHome) {
        this.takeHome = takeHome;
    }

    /** {salary, state, k401Percent, preTaxHealth (per year), payPeriods} → yearly and per-paycheck amounts */
    @PostMapping("/take-home")
    public ResponseEntity<Map<String, Object>> takeHome(@RequestBody Map<String, Object> body) {
        double salary = number(body.get("salary"));
        int payPeriods = (int) number(body.getOrDefault("payPeriods", 26));
        if (salary < 0 || salary > 100_000_000 || !List.of(1, 12, 24, 26, 52).contains(payPeriods)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Enter a yearly salary and how often you're paid."));
        }
        double k401 = Math.min(100, Math.max(0, number(body.get("k401Percent"))));
        double health = Math.max(0, number(body.get("preTaxHealth")));
        String state = body.get("state") == null ? null : String.valueOf(body.get("state"));
        TakeHomeCalculator.Result result = takeHome.calculate(salary, state, k401, health);
        Map<String, Object> out = result.toMap(payPeriods);
        out.put("k401Limit", takeHome.k401Limit());
        return ResponseEntity.ok(out);
    }

    /** the states the calculator knows: [{code, name, note?}] */
    @GetMapping("/states")
    public List<Map<String, String>> states() {
        List<Map<String, String>> out = new ArrayList<>();
        takeHome.states().fields().forEachRemaining(entry -> {
            Map<String, String> m = new LinkedHashMap<>();
            m.put("code", entry.getKey());
            m.put("name", entry.getValue().path("name").asText());
            if (entry.getValue().has("note")) m.put("note", entry.getValue().path("note").asText());
            out.add(m);
        });
        out.sort((a, b) -> a.get("name").compareTo(b.get("name")));
        return out;
    }

    private static double number(Object value) {
        if (value instanceof Number n) return n.doubleValue();
        try {
            return value == null ? 0 : Double.parseDouble(String.valueOf(value).replace(",", "").replace("$", "").strip());
        } catch (NumberFormatException e) {
            return 0;
        }
    }
}
