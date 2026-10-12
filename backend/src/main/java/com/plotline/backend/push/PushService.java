package com.plotline.backend.push;

import static com.plotline.backend.util.UsernameUtils.normalize;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Push notifications to people's phones: friend requests, invites, chat replies, the weekly
 * budget recap. Sending happens in the background, so the request that caused it isn't slowed
 * down and a push failure never fails it.
 */
@Service
public class PushService {
    private static final Logger log = LoggerFactory.getLogger(PushService.class);

    /** a notification; `destination` is the screen tapping it opens (friends, calendar, grocery, budget) */
    public record Message(String title, String body, String destination) { }

    private final JdbcTemplate jdbc;
    private final ApnsClient apns;
    private final ObjectMapper json = new ObjectMapper();
    private final ExecutorService sender = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "push-sender");
        t.setDaemon(true);
        return t;
    });

    public PushService(JdbcTemplate jdbc, ApnsClient apns) {
        this.jdbc = jdbc;
        this.apns = apns;
    }

    // ── phones ─────────────────────────────────────────────────────────────

    /** this phone gets `username`'s notifications (a phone belongs to whoever signed in last) */
    public void registerDevice(String username, String token, String environment, String timeZone) {
        jdbc.update("""
            insert into push_devices (token, username, environment, time_zone, updated_at) values (?, ?, ?, ?, now())
            on conflict (token) do update set username = excluded.username, environment = excluded.environment,
                time_zone = excluded.time_zone, updated_at = now()
            """, token, normalize(username), "sandbox".equals(environment) ? "sandbox" : "production", timeZone);
    }

    /** signed out on this phone */
    public void removeDevice(String username, String token) {
        jdbc.update("delete from push_devices where token = ? and username = ?", token, normalize(username));
    }

    /** account deleted */
    public void removeAllDevices(String username) {
        jdbc.update("delete from push_devices where username = ?", normalize(username));
        jdbc.update("delete from weekly_recaps where username = ?", normalize(username));
    }

    // ── sending ────────────────────────────────────────────────────────────

    /** to every phone `username` is signed in on; never throws */
    public void send(String username, Message message) {
        if (username == null || !apns.isConfigured()) return;
        String user = normalize(username);
        sender.submit(() -> deliver(user, message));
    }

    void deliver(String username, Message message) {
        try {
            List<Map<String, Object>> devices = jdbc.queryForList(
                    "select token, environment from push_devices where username = ?", username);
            if (devices.isEmpty()) return;
            String payload = payload(message);
            for (Map<String, Object> device : devices) {
                String token = (String) device.get("token");
                ApnsClient.Result result = apns.send(token, (String) device.get("environment"), payload);
                if (result == ApnsClient.Result.BAD_TOKEN) {
                    jdbc.update("delete from push_devices where token = ?", token); // app deleted
                }
            }
        } catch (Exception e) {
            log.warn("Push to {} failed ({})", username, e.toString());
        }
    }

    String payload(Message message) throws Exception {
        Map<String, Object> alert = new LinkedHashMap<>();
        alert.put("title", message.title());
        alert.put("body", message.body());
        Map<String, Object> aps = new LinkedHashMap<>();
        aps.put("alert", alert);
        aps.put("sound", "default");
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("aps", aps);
        if (message.destination() != null) body.put("destination", message.destination());
        return json.writeValueAsString(body);
    }
}
