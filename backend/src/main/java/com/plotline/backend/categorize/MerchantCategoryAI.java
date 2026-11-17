package com.plotline.backend.categorize;

import java.io.ByteArrayInputStream;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.service.OpenAIService;
import com.plotline.backend.service.S3Service;

/**
 * Sorting the transactions the bank couldn't label: gpt-4o-mini picks one of the standard categories
 * from the merchant name (only names are sent, no amounts). Each answer is remembered per user
 * (users/{u}/merchant-categories.json, removed with the account), so a merchant is asked about once.
 * It's PlotLine's own background work: it doesn't count toward anyone's daily AI limit.
 */
@Component
public class MerchantCategoryAI {
    private static final Logger log = LoggerFactory.getLogger(MerchantCategoryAI.class);

    /** at most this many new merchants per question (and per sync or summary) */
    static final int BATCH = 40;

    private final OpenAIService openAI;
    private final S3Service s3;
    private final ObjectMapper mapper = new ObjectMapper();
    private final Map<String, Map<String, String>> cache = new ConcurrentHashMap<>();

    public MerchantCategoryAI(OpenAIService openAI, S3Service s3) {
        this.openAI = openAI;
        this.s3 = s3;
    }

    private static String key(String username) {
        return "users/%s/merchant-categories.json".formatted(username.toLowerCase());
    }

    /** the remembered category for a merchant (upper-cased, trimmed), or null */
    public String lookup(String username, String merchant) {
        return load(username).get(merchant);
    }

    /** asks about the merchants it hasn't seen yet; nothing happens when OpenAI isn't available */
    public void classify(String username, Collection<String> merchants, List<String> categories) {
        Map<String, String> known = load(username);
        List<String> unknown = merchants.stream().filter(m -> m != null && !m.isBlank() && !known.containsKey(m))
                .distinct().limit(BATCH).toList();
        if (unknown.isEmpty()) return;
        try {
            String answer = openAI.estimateJson("""
                    You sort bank transactions into budget categories. For each merchant name (one per line), pick \
                    exactly one category from this list: %s. Use "Miscellaneous" when you can't tell. Answer with \
                    JSON only: {"categories": {"<merchant name exactly as given>": "<category>"}}""".formatted(String.join(", ", categories)),
                    String.join("\n", unknown), 1500);
            if (answer == null || answer.isBlank()) return;
            JsonNode picked = mapper.readTree(answer).path("categories");
            for (String merchant : unknown) {
                String category = picked.path(merchant).asText("");
                known.put(merchant, categories.contains(category) ? category : "Miscellaneous");
            }
            save(username, known);
        } catch (Exception e) {
            log.warn("Sorting {} merchants with AI failed: {}", unknown.size(), e.getMessage());
        }
    }

    // ── narrower categories (a bar out of Eating Out) ─────────────────────────────

    private final Map<String, Map<String, String>> nicheCache = new ConcurrentHashMap<>();

    private static String nicheKey(String username) {
        return "users/%s/merchant-niches.json".formatted(username.toLowerCase());
    }

    /** the narrower category the AI picked for a merchant, or null (none, or not asked yet) */
    public String lookupNiche(String username, String merchant) {
        String picked = loadNiches(username).get(merchant);
        return picked == null || picked.isBlank() ? null : picked;
    }

    /**
     * For merchants their bank label and name don't place: which narrower category each is, from the
     * ones its broad category has (merchant → options), or none. Only names are sent; remembered per user.
     */
    public void classifyNiches(String username, Map<String, List<String>> options, Map<String, String> meanings) {
        Map<String, String> known = loadNiches(username);
        List<String> unknown = options.keySet().stream().filter(m -> m != null && !m.isBlank() && !known.containsKey(m))
                .distinct().limit(BATCH * 4L).toList();
        boolean changed = false;
        for (int from = 0; from < unknown.size(); from += BATCH) {
            List<String> batch = unknown.subList(from, Math.min(unknown.size(), from + BATCH));
            StringBuilder lines = new StringBuilder();
            java.util.Set<String> mentioned = new java.util.TreeSet<>();
            for (String m : batch) {
                lines.append(m).append(" -> ").append(String.join(", ", options.get(m))).append('\n');
                mentioned.addAll(options.get(m));
            }
            List<String> hints = mentioned.stream().filter(meanings::containsKey).map(n -> n + " = " + meanings.get(n)).toList();
            try {
                String answer = openAI.estimateJson("""
                        You sort purchases into narrower budget categories. Each line is a merchant name, then "->" and the                         narrower categories it could go in. Answer the one it clearly is, or "none" if it isn't clearly one                         of them (most places are none: an ordinary restaurant isn't a bar or fast food). %sAnswer with JSON only:                         {"categories": {"<merchant name exactly as given>": "<category or none>"}}"""
                                .formatted(hints.isEmpty() ? "" : "What some mean: " + String.join("; ", hints) + ". "),
                        lines.toString(), 1500);
                if (answer == null || answer.isBlank()) break;
                JsonNode picked = mapper.readTree(answer).path("categories");
                for (String merchant : batch) {
                    String niche = picked.path(merchant).asText("");
                    known.put(merchant, options.get(merchant).stream().filter(o -> o.equalsIgnoreCase(niche)).findFirst().orElse(""));
                }
                changed = true;
            } catch (Exception e) {
                log.warn("Picking narrower categories for {} merchants failed: {}", batch.size(), e.getMessage());
                break;
            }
        }
        if (changed) {
            try {
                byte[] json = mapper.writeValueAsBytes(new LinkedHashMap<>(known));
                s3.uploadFile(nicheKey(username), new ByteArrayInputStream(json), json.length);
            } catch (Exception e) {
                log.warn("Saving narrower categories failed: {}", e.getMessage());
            }
        }
    }

    private Map<String, String> loadNiches(String username) {
        return nicheCache.computeIfAbsent(username.toLowerCase(), u -> {
            try {
                byte[] data = s3.downloadFile(nicheKey(u));
                if (data != null && data.length > 0) return new ConcurrentHashMap<>(mapper.readValue(data, new TypeReference<Map<String, String>>() { }));
            } catch (Exception ignored) {
                // none yet
            }
            return new ConcurrentHashMap<>();
        });
    }

    // ── their own categories ("Golf", "Date Night") ─────────────────────────────

    /** {categories: [their own, sorted], merchants: {MERCHANT: category or ""}}: asked again when the categories change */
    private final Map<String, Map<String, Object>> customCache = new ConcurrentHashMap<>();

    private static String customKey(String username) {
        return "users/%s/merchant-custom-categories.json".formatted(username.toLowerCase());
    }

    /** the category of their own a merchant belongs to, or null (most belong to none) */
    @SuppressWarnings("unchecked")
    public String lookupCustom(String username, String merchant) {
        Map<String, Object> saved = loadCustom(username);
        Object picked = ((Map<String, String>) saved.getOrDefault("merchants", Map.of())).get(merchant);
        return picked instanceof String c && !c.isBlank() ? c : null;
    }

    /**
     * Which merchants belong in their own categories, for the ones not asked about yet (up to 4 questions
     * per call). Only names are sent. When their categories change, everything is asked again.
     */
    @SuppressWarnings("unchecked")
    public void classifyCustom(String username, Collection<String> merchants, List<String> categories) {
        List<String> wanted = categories.stream().sorted().toList();
        Map<String, Object> saved = loadCustom(username);
        if (!wanted.equals(saved.get("categories"))) {
            saved = new ConcurrentHashMap<>(Map.of("categories", wanted, "merchants", new ConcurrentHashMap<String, String>()));
            customCache.put(username.toLowerCase(), saved);
        }
        Map<String, String> known = (Map<String, String>) saved.get("merchants");
        List<String> unknown = merchants.stream().filter(m -> m != null && !m.isBlank() && !known.containsKey(m)).distinct().limit(BATCH * 4L).toList();
        boolean changed = false;
        for (int from = 0; from < unknown.size(); from += BATCH) {
            List<String> batch = unknown.subList(from, Math.min(unknown.size(), from + BATCH));
            try {
                String answer = openAI.estimateJson("""
                        Someone's budget has these categories of their own: %s. For each merchant name (one per line),                         answer the one of those categories it clearly belongs to, or "none" if it doesn't clearly fit one                         (most merchants won't). Answer with JSON only: {"categories": {"<merchant name exactly as given>": "<category or none>"}}"""
                                .formatted(String.join(", ", wanted)),
                        String.join("\n", batch), 1500);
                if (answer == null || answer.isBlank()) break;
                JsonNode picked = mapper.readTree(answer).path("categories");
                for (String merchant : batch) {
                    String category = picked.path(merchant).asText("");
                    known.put(merchant, wanted.stream().filter(c -> c.equalsIgnoreCase(category)).findFirst().orElse(""));
                }
                changed = true;
            } catch (Exception e) {
                log.warn("Matching {} merchants to their own categories failed: {}", batch.size(), e.getMessage());
                break;
            }
        }
        if (changed) {
            try {
                byte[] json = mapper.writeValueAsBytes(Map.of("categories", wanted, "merchants", new LinkedHashMap<>(known)));
                s3.uploadFile(customKey(username), new ByteArrayInputStream(json), json.length);
            } catch (Exception e) {
                log.warn("Saving merchants matched to their own categories failed: {}", e.getMessage());
            }
        }
    }

    private Map<String, Object> loadCustom(String username) {
        return customCache.computeIfAbsent(username.toLowerCase(), u -> {
            try {
                byte[] data = s3.downloadFile(customKey(u));
                if (data != null && data.length > 0) {
                    JsonNode saved = mapper.readTree(data);
                    List<String> categories = new java.util.ArrayList<>();
                    saved.path("categories").forEach(c -> categories.add(c.asText()));
                    Map<String, String> merchants = new ConcurrentHashMap<>();
                    saved.path("merchants").fields().forEachRemaining(e -> merchants.put(e.getKey(), e.getValue().asText("")));
                    return new ConcurrentHashMap<>(Map.of("categories", categories, "merchants", merchants));
                }
            } catch (Exception ignored) {
                // none yet
            }
            return new ConcurrentHashMap<>(Map.of("categories", List.of(), "merchants", new ConcurrentHashMap<String, String>()));
        });
    }

    private Map<String, String> load(String username) {
        return cache.computeIfAbsent(username.toLowerCase(), u -> {
            try {
                byte[] data = s3.downloadFile(key(u));
                if (data != null && data.length > 0) return new ConcurrentHashMap<>(mapper.readValue(data, new TypeReference<Map<String, String>>() { }));
            } catch (Exception ignored) {
                // none yet
            }
            return new ConcurrentHashMap<>();
        });
    }

    private void save(String username, Map<String, String> known) {
        try {
            byte[] json = mapper.writeValueAsBytes(new LinkedHashMap<>(known));
            s3.uploadFile(key(username), new ByteArrayInputStream(json), json.length);
        } catch (Exception e) {
            log.warn("Saving sorted merchants failed: {}", e.getMessage());
        }
    }
}
