package com.plotline.backend.testsupport;

import java.io.IOException;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.concurrent.atomic.AtomicInteger;

import javax.sql.DataSource;

import org.flywaydb.core.Flyway;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;

/**
 * A real Postgres (the same major version as Neon) started once per test run, without Docker.
 * Each caller gets its own empty database, so tests never see each other's rows.
 */
public final class TestDatabase {

    private static EmbeddedPostgres server;
    private static final AtomicInteger counter = new AtomicInteger();

    private TestDatabase() { }

    private static synchronized EmbeddedPostgres server() {
        if (server == null) {
            try {
                server = EmbeddedPostgres.builder().start();
            } catch (IOException e) {
                throw new IllegalStateException("Couldn't start the test database", e);
            }
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                try { server.close(); } catch (IOException ignored) { }
            }));
        }
        return server;
    }

    /** a new, empty database's JDBC URL (Spring applies the migrations itself) */
    public static String newDatabaseUrl() {
        String name = "plotline_test_" + counter.incrementAndGet();
        try (Connection connection = server().getPostgresDatabase().getConnection();
             Statement statement = connection.createStatement()) {
            statement.execute("create database " + name);
        } catch (SQLException e) {
            throw new IllegalStateException("Couldn't create test database " + name, e);
        }
        return server().getJdbcUrl("postgres", name);
    }

    /** a new database with PlotLine's tables, for tests that build services by hand */
    public static DataSource newDatabase() {
        String url = newDatabaseUrl();
        String name = url.substring(url.lastIndexOf('/') + 1).split("\\?")[0];
        DataSource dataSource = server().getDatabase("postgres", name);
        Flyway.configure().dataSource(dataSource).load().migrate();
        return dataSource;
    }
}
