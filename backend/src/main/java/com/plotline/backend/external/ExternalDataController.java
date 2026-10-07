package com.plotline.backend.external;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;

import io.github.cdimascio.dotenv.Dotenv;

/**
 * Market news (NewsAPI) and food search (USDA FoodData Central), fetched by the server so their
 * API keys stay on the server (Fly secrets NEWS_API_KEY and USDA_FDC_API_KEY) instead of shipping
 * inside the app. Results are cached: news is the same for everyone (and NewsAPI's free plan
 * allows ~100 requests a day), and food searches repeat a lot.
 */
@RestController
public class ExternalDataController {

    private static final Logger log = LoggerFactory.getLogger(ExternalDataController.class);

    // the portfolio's risk level picks the news topic
    static final Map<String, String> NEWS_TOPICS = Map.of(
            "low", "long term investing",
            "medium", "stock market investing",
            "high", "growth stocks OR speculative tech");

    private final ExternalDataClient client;
    private final String newsApiKey;
    private final String usdaApiKey;
    private final ObjectMapper mapper = new ObjectMapper();

    private final Cache<String, String> newsCache = Caffeine.newBuilder()
            .expireAfterWrite(Duration.ofHours(1))
            .build();
    private final Cache<String, String> foodCache = Caffeine.newBuilder()
            .expireAfterWrite(Duration.ofDays(1))
            .maximumSize(5_000)
            .build();

    @Autowired
    public ExternalDataController(ExternalDataClient client) {
        this(client, env("NEWS_API_KEY"), env("USDA_FDC_API_KEY"));
    }

    // for tests
    ExternalDataController(ExternalDataClient client, String newsApiKey, String usdaApiKey) {
        this.client = client;
        this.newsApiKey = newsApiKey;
        // USDA's shared demo key works (with low limits) until a real one is set
        this.usdaApiKey = usdaApiKey == null || usdaApiKey.isBlank() ? "DEMO_KEY" : usdaApiKey;
        if (newsApiKey == null || newsApiKey.isBlank()) log.warn("NEWS_API_KEY not set; market news is disabled");
    }

    private static String env(String name) {
        String value = System.getenv(name);
        return value != null && !value.isBlank() ? value : Dotenv.configure().ignoreIfMissing().load().get(name);
    }

    /** {"articles": [{"title", "description", "url"}]} for a risk level: low, medium (default) or high */
    @GetMapping("/api/news")
    public ResponseEntity<String> news(@RequestParam(defaultValue = "medium") String risk) {
        if (newsApiKey == null || newsApiKey.isBlank()) {
            return error(HttpStatus.SERVICE_UNAVAILABLE, "News isn't available right now.");
        }
        String topic = NEWS_TOPICS.getOrDefault(risk.trim().toLowerCase(), NEWS_TOPICS.get("medium"));
        try {
            return json(newsCache.get(topic, this::fetchNews));
        } catch (UncheckedIOException e) {
            log.warn("News fetch failed: {}", e.getCause().getMessage());
            return error(HttpStatus.BAD_GATEWAY, "Couldn't load news. Please try again.");
        }
    }

    private String fetchNews(String topic) {
        try {
            String url = "https://newsapi.org/v2/everything?q=" + encode(topic)
                    + "&sortBy=publishedAt&language=en&pageSize=30&apiKey=" + encode(newsApiKey);
            JsonNode body = mapper.readTree(client.get(url));
            List<Map<String, String>> articles = new ArrayList<>();
            for (JsonNode a : body.path("articles")) {
                String title = a.path("title").asText("");
                String link = a.path("url").asText("");
                if (title.isBlank() || link.isBlank() || "[Removed]".equals(title)) continue;
                Map<String, String> article = new LinkedHashMap<>();
                article.put("title", title);
                if (a.hasNonNull("description")) article.put("description", a.get("description").asText());
                article.put("url", link);
                articles.add(article);
            }
            return mapper.writeValueAsString(Map.of("articles", articles));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** USDA FoodData Central search results, as USDA returns them (25 per page) */
    @GetMapping("/api/nutrition/food-search")
    public ResponseEntity<String> foodSearch(@RequestParam(name = "q", defaultValue = "") String query) {
        String q = query.trim().toLowerCase();
        if (q.isEmpty()) return json("{\"foods\":[]}");
        if (q.length() > 100) q = q.substring(0, 100);
        try {
            return json(foodCache.get(q, this::fetchFoods));
        } catch (UncheckedIOException e) {
            log.warn("Food search failed: {}", e.getCause().getMessage());
            return error(HttpStatus.BAD_GATEWAY, "Couldn't search foods. Please try again.");
        }
    }

    private String fetchFoods(String q) {
        try {
            return client.get("https://api.nal.usda.gov/fdc/v1/foods/search?query=" + encode(q)
                    + "&pageSize=25&api_key=" + encode(usdaApiKey));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static String encode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    private static ResponseEntity<String> json(String body) {
        return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(body);
    }

    private ResponseEntity<String> error(HttpStatus status, String message) {
        try {
            return ResponseEntity.status(status).contentType(MediaType.APPLICATION_JSON)
                    .body(mapper.writeValueAsString(Map.of("success", false, "error", message)));
        } catch (IOException e) {
            return ResponseEntity.status(status).build();
        }
    }
}
