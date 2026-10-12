package com.plotline.backend.service;

import java.time.Duration;
import java.time.Instant;
import java.sql.Timestamp;
import java.util.List;
import java.util.Locale;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/**
 * Grocery prices are AI estimates. Each item's price for a region is kept here (Postgres), so the
 * same item costs the same on every list and for everyone in that state, without asking the AI each
 * time. A price older than two weeks is estimated again, so prices follow real changes.
 */
@Component
public class GroceryPriceCache {

    public static final Duration MAX_AGE = Duration.ofDays(14);

    @FunctionalInterface
    public interface Estimator {
        double unitPrice() throws Exception;
    }

    private final JdbcTemplate jdbc;

    public GroceryPriceCache(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** the price of one `item` in `location`, estimated (and saved) when missing or stale */
    public double unitPrice(String item, String location, Estimator estimator) throws Exception {
        String key = normalizeItem(item);
        String region = region(location);
        List<Double> fresh = jdbc.queryForList(
                "select unit_price from grocery_prices where item = ? and region = ? and updated_at > ?",
                Double.class, key, region, Timestamp.from(Instant.now().minus(MAX_AGE)));
        if (!fresh.isEmpty()) return fresh.get(0);

        double price = Math.round(estimator.unitPrice() * 100) / 100.0;
        if (price > 0) {
            jdbc.update("""
                insert into grocery_prices (item, region, unit_price, updated_at) values (?, ?, ?, now())
                on conflict (item, region) do update set unit_price = excluded.unit_price, updated_at = now()
                """, key, region, price);
        }
        return price;
    }

    /** "  Whole  Milk!" → "whole milk" */
    static String normalizeItem(String item) {
        return item == null ? "" : item.toLowerCase(Locale.ROOT).replaceAll("[^\\p{L}\\p{N}% ]", " ")
                .replaceAll("\\s+", " ").strip();
    }

    /** "Columbus, Ohio" → "ohio": prices vary by state more than by city */
    static String region(String location) {
        if (location == null || location.isBlank()) return "united states";
        String[] parts = location.split(",");
        return parts[parts.length - 1].strip().toLowerCase(Locale.ROOT);
    }
}
