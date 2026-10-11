package com.plotline.backend.accounts;

import com.plotline.backend.testsupport.TestDatabase;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.bind.Bindable;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.context.properties.source.MapConfigurationPropertySource;
import org.springframework.core.io.ClassPathResource;
import org.springframework.core.io.support.PropertiesLoaderUtils;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.sql.Connection;
import java.sql.Statement;
import java.time.Duration;
import java.util.List;
import java.util.Properties;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Fly suspends the server when it's idle, and Neon drops its connections meanwhile. On wake-up
 * the pool's old connections look open but never answer. With the old settings the first
 * requests waited 30-50s on them. These tests use the real application.properties settings.
 */
class DatabasePoolTest {

    @Test
    @DisplayName("Idle connections are closed before Fly suspends the server, and retired before Neon's cut-off")
    void noConnectionsKeptAcrossASuspend() throws IOException {
        HikariConfig config = appPoolSettings();
        assertThat(config.getMinimumIdle()).isZero();
        assertThat(Duration.ofMillis(config.getIdleTimeout())).isLessThanOrEqualTo(Duration.ofSeconds(30));
        assertThat(Duration.ofMillis(config.getMaxLifetime())).isLessThan(Duration.ofMinutes(5));
    }

    @Test
    @DisplayName("A request right after waking up gets a fresh connection quickly instead of waiting on a dead one")
    void deadConnectionIsReplacedQuickly() throws Exception {
        String url = TestDatabase.newDatabaseUrl(); // jdbc:postgresql://localhost:<port>/<db>?...
        int port = Integer.parseInt(url.replaceFirst("^jdbc:postgresql://[^:]+:(\\d+)/.*$", "$1"));

        try (FreezableProxy proxy = new FreezableProxy(port)) {
            HikariConfig config = appPoolSettings();
            config.setJdbcUrl(url.replaceFirst(":" + port + "/", ":" + proxy.port() + "/"));
            try (HikariDataSource pool = new HikariDataSource(config)) {
                query(pool); // a connection now sits in the pool

                proxy.freezeExisting(); // the server "slept": that connection is dead but still looks open
                Thread.sleep(600);      // long enough that the pool re-checks it before handing it out

                long start = System.nanoTime();
                query(pool);
                assertThat(Duration.ofNanos(System.nanoTime() - start)).isLessThan(Duration.ofSeconds(4));
            }
        }
    }

    private static void query(HikariDataSource pool) throws Exception {
        try (Connection c = pool.getConnection(); Statement s = c.createStatement()) {
            s.execute("select 1");
        }
    }

    // the spring.datasource.hikari.* settings from application.properties
    private static HikariConfig appPoolSettings() throws IOException {
        Properties props = PropertiesLoaderUtils.loadProperties(new ClassPathResource("application.properties"));
        HikariConfig config = new HikariConfig();
        new Binder(new MapConfigurationPropertySource(props))
                .bind("spring.datasource.hikari", Bindable.ofInstance(config));
        return config;
    }

    /** A TCP pass-through that can silently stop forwarding on the connections open so far. */
    private static final class FreezableProxy implements AutoCloseable {
        private final ServerSocket listener = new ServerSocket(0);
        private final List<AtomicBoolean> frozen = new CopyOnWriteArrayList<>();
        private final List<Socket> sockets = new CopyOnWriteArrayList<>();

        FreezableProxy(int targetPort) throws IOException {
            Thread acceptor = new Thread(() -> {
                while (!listener.isClosed()) {
                    try {
                        Socket client = listener.accept();
                        Socket server = new Socket("localhost", targetPort);
                        sockets.add(client);
                        sockets.add(server);
                        AtomicBoolean isFrozen = new AtomicBoolean(false);
                        frozen.add(isFrozen);
                        pump(client.getInputStream(), server.getOutputStream(), isFrozen);
                        pump(server.getInputStream(), client.getOutputStream(), isFrozen);
                    } catch (IOException e) {
                        return;
                    }
                }
            });
            acceptor.setDaemon(true);
            acceptor.start();
        }

        int port() { return listener.getLocalPort(); }

        void freezeExisting() { frozen.forEach(f -> f.set(true)); }

        private static void pump(InputStream in, OutputStream out, AtomicBoolean isFrozen) {
            Thread t = new Thread(() -> {
                byte[] buffer = new byte[8192];
                try {
                    int n;
                    while ((n = in.read(buffer)) != -1) {
                        if (isFrozen.get()) continue; // swallow: nothing gets through, nothing closes
                        out.write(buffer, 0, n);
                        out.flush();
                    }
                } catch (IOException ignored) { }
            });
            t.setDaemon(true);
            t.start();
        }

        @Override
        public void close() throws IOException {
            listener.close();
            for (Socket s : sockets) s.close();
        }
    }
}
