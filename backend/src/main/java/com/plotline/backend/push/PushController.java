package com.plotline.backend.push;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.ZonedDateTime;
import java.time.ZoneOffset;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.plotline.backend.security.CurrentUser;

import io.github.cdimascio.dotenv.Dotenv;

@RestController
public class PushController {

    private final PushService push;
    private final WeeklyRecapService recaps;
    private final String cronToken;

    public PushController(PushService push, WeeklyRecapService recaps) {
        this.push = push;
        this.recaps = recaps;
        String token = System.getenv("CRON_TOKEN");
        if (token == null || token.isBlank()) token = Dotenv.configure().ignoreIfMissing().load().get("CRON_TOKEN");
        this.cronToken = token == null || token.isBlank() ? null : token.strip();
    }

    /** this phone gets the signed-in person's notifications: {token, environment, timeZone} */
    @PostMapping("/api/push/devices")
    public ResponseEntity<Void> register(@RequestBody Map<String, String> body) {
        String token = body.get("token");
        if (token == null || !token.matches("[0-9a-fA-F]{32,200}")) return ResponseEntity.badRequest().build();
        push.registerDevice(CurrentUser.require(), token.toLowerCase(), body.get("environment"), body.get("timeZone"));
        return ResponseEntity.ok().build();
    }

    /** signing out on this phone */
    @DeleteMapping("/api/push/devices")
    public ResponseEntity<Void> unregister(@RequestParam String token) {
        push.removeDevice(CurrentUser.require(), token.toLowerCase());
        return ResponseEntity.ok().build();
    }

    /** the weekly recap timer (a GitHub Actions schedule), proven with the CRON_TOKEN secret */
    @PostMapping("/internal/weekly-recap")
    public ResponseEntity<Map<String, Object>> weeklyRecap(@RequestHeader(value = "X-Cron-Token", required = false) String token) {
        if (cronToken == null || token == null
                || !MessageDigest.isEqual(cronToken.getBytes(StandardCharsets.UTF_8), token.getBytes(StandardCharsets.UTF_8))) {
            return ResponseEntity.status(403).build();
        }
        return ResponseEntity.ok(Map.of("sent", recaps.run(ZonedDateTime.now(ZoneOffset.UTC))));
    }
}
