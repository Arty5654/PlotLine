package com.plotline.backend.external;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.function.Supplier;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/**
 * Fetches JSON from outside services (NewsAPI, USDA). Tests replace it with a fake.
 *
 * Fly suspends this server when it's idle; on wake-up the HTTP client's open connections are
 * dead and every request failed at once (an IOException with no message) until a restart. So a
 * request that fails before getting any answer is retried once on a fresh client.
 */
@Component
public class ExternalDataClient {
    private static final Logger log = LoggerFactory.getLogger(ExternalDataClient.class);

    /** the service answered, but not with 2xx (not retried: asking again won't change the answer) */
    public static class BadStatusException extends IOException {
        public BadStatusException(String message) { super(message); }
    }

    private final Supplier<HttpClient> clients;
    private volatile HttpClient http;

    @Autowired
    public ExternalDataClient() {
        this(() -> HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build());
    }

    ExternalDataClient(Supplier<HttpClient> clients) {
        this.clients = clients;
        this.http = clients.get();
    }

    /** the response body, or IOException if the service didn't answer 2xx */
    public String get(String url) throws IOException {
        return fetch(base(url).GET().build());
    }

    /** POSTs a JSON body; the response body, or IOException if the service didn't answer 2xx */
    public String postJson(String url, String json) throws IOException {
        return fetch(base(url).header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(json)).build());
    }

    private static HttpRequest.Builder base(String url) {
        return HttpRequest.newBuilder(URI.create(url))
                .timeout(Duration.ofSeconds(10))
                .header("Accept", "application/json")
                .header("User-Agent", "PlotLine-Backend");
    }

    private String fetch(HttpRequest request) throws IOException {
        try {
            return send(http, request);
        } catch (BadStatusException e) {
            throw e;
        } catch (IOException e) {
            log.warn("Request to {} failed ({}); retrying on a fresh connection", request.uri().getHost(), e.toString());
            HttpClient stale = http;
            http = clients.get();
            stale.shutdownNow(); // don't wait on its dead connections
            return send(http, request);
        }
    }

    private static String send(HttpClient client, HttpRequest request) throws IOException {
        try {
            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() / 100 != 2) {
                throw new BadStatusException("HTTP " + response.statusCode() + " from " + request.uri().getHost());
            }
            return response.body();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IOException("Interrupted", e);
        }
    }
}
