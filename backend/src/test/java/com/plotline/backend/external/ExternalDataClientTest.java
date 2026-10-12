package com.plotline.backend.external;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.net.InetSocketAddress;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ExternalDataClientTest {

    private HttpServer server;
    private String base;

    @BeforeEach
    void start() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/ok", ex -> {
            byte[] body = "{\"foods\":[]}".getBytes(StandardCharsets.UTF_8);
            ex.sendResponseHeaders(200, body.length);
            ex.getResponseBody().write(body);
            ex.close();
        });
        server.createContext("/denied", ex -> { ex.sendResponseHeaders(403, -1); ex.close(); });
        server.start();
        base = "http://127.0.0.1:" + server.getAddress().getPort();
    }

    @AfterEach
    void stop() { server.stop(0); }

    @Test
    @DisplayName("A client that died (e.g. after Fly suspended the server) is replaced and the request retried")
    void deadClientIsReplaced() throws Exception {
        AtomicInteger made = new AtomicInteger();
        ExternalDataClient client = new ExternalDataClient(() -> {
            HttpClient c = HttpClient.newHttpClient();
            if (made.getAndIncrement() == 0) c.close(); // the first one is already dead
            return c;
        });

        assertThat(client.get(base + "/ok")).isEqualTo("{\"foods\":[]}");
        assertThat(made.get()).isEqualTo(2);
        assertThat(client.get(base + "/ok")).isEqualTo("{\"foods\":[]}"); // keeps using the fresh one
        assertThat(made.get()).isEqualTo(2);
    }

    @Test
    @DisplayName("A refusal from the service (e.g. 403) isn't retried")
    void badStatusIsNotRetried() {
        AtomicInteger made = new AtomicInteger();
        ExternalDataClient client = new ExternalDataClient(() -> { made.incrementAndGet(); return HttpClient.newHttpClient(); });

        assertThatThrownBy(() -> client.get(base + "/denied"))
                .isInstanceOf(ExternalDataClient.BadStatusException.class)
                .hasMessageContaining("403");
        assertThat(made.get()).isEqualTo(1);
    }
}
