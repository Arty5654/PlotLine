package com.plotline.backend.push;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import io.github.cdimascio.dotenv.Dotenv;

/**
 * Sends notifications through Apple's push service (APNs) with a token-based key: an ES256-signed
 * JWT made from the .p8 key in Apple Developer → Keys. Needs APNS_KEY_ID, APNS_TEAM_ID and
 * APNS_PRIVATE_KEY (the .p8 file's contents); without them nothing is sent.
 */
@Component
public class ApnsClient {
    private static final Logger log = LoggerFactory.getLogger(ApnsClient.class);

    /** what Apple said about one notification */
    public enum Result { SENT, BAD_TOKEN, FAILED, NOT_CONFIGURED }

    private final String keyId;
    private final String teamId;
    private final String topic;
    private final PrivateKey key;
    private final HttpClient http = HttpClient.newBuilder()
            .version(HttpClient.Version.HTTP_2)
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    private String jwt;
    private Instant jwtMadeAt = Instant.EPOCH;

    public ApnsClient() {
        Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();
        // a push-only key if one is set; otherwise the Sign in with Apple key, which works when
        // "Apple Push Notifications service" is also enabled on it (the team is the same either way)
        boolean ownKey = env(dotenv, "APNS_KEY_ID") != null;
        this.keyId = ownKey ? env(dotenv, "APNS_KEY_ID") : env(dotenv, "APPLE_KEY_ID");
        this.teamId = env(dotenv, "APNS_TEAM_ID") != null ? env(dotenv, "APNS_TEAM_ID") : env(dotenv, "APPLE_TEAM_ID");
        String topicSetting = env(dotenv, "APNS_TOPIC");
        this.topic = topicSetting != null ? topicSetting : "com.ArteomAvetissian.PlotLine";
        this.key = parseKey(env(dotenv, ownKey ? "APNS_PRIVATE_KEY" : "APPLE_PRIVATE_KEY"));
        if (!isConfigured()) {
            log.info("Push notifications are off: no APNS_* (or APPLE_*) key, team and private key are set");
        } else {
            log.info("Push notifications use key {} ({})", keyId, ownKey ? "APNS_KEY_ID" : "the Sign in with Apple key");
        }
    }

    public boolean isConfigured() {
        return keyId != null && teamId != null && key != null;
    }

    /** one notification to one phone; `payload` is the JSON body ({"aps": {...}, ...}) */
    public Result send(String deviceToken, String environment, String payload) {
        if (!isConfigured()) return Result.NOT_CONFIGURED;
        String host = "sandbox".equals(environment) ? "api.sandbox.push.apple.com" : "api.push.apple.com";
        try {
            HttpRequest request = HttpRequest.newBuilder(URI.create("https://" + host + "/3/device/" + deviceToken))
                    .timeout(Duration.ofSeconds(15))
                    .header("authorization", "bearer " + token())
                    .header("apns-topic", topic)
                    .header("apns-push-type", "alert")
                    .header("apns-priority", "10")
                    .POST(HttpRequest.BodyPublishers.ofString(payload, StandardCharsets.UTF_8))
                    .build();
            HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 200) return Result.SENT;
            String reason = response.body();
            // the app was deleted, or the token is from the other environment / another app
            if (response.statusCode() == 410 || reason.contains("BadDeviceToken") || reason.contains("Unregistered")
                    || reason.contains("DeviceTokenNotForTopic")) {
                return Result.BAD_TOKEN;
            }
            if (reason.contains("InvalidProviderToken")) {
                log.error("APNs rejected key {}: it doesn't have Apple Push Notifications service enabled, or the key/team ID is wrong. "
                        + "Create a key with APNs in Apple Developer → Keys and set APNS_KEY_ID / APNS_PRIVATE_KEY.", keyId);
            } else {
                log.warn("APNs refused a notification: {} {}", response.statusCode(), reason);
            }
            return Result.FAILED;
        } catch (Exception e) {
            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
            log.warn("APNs request failed ({})", e.toString());
            return Result.FAILED;
        }
    }

    /** Apple wants a token newer than an hour and not remade more than every 20 minutes */
    private synchronized String token() throws Exception {
        if (jwt != null && Duration.between(jwtMadeAt, Instant.now()).toMinutes() < 45) return jwt;
        Base64.Encoder b64 = Base64.getUrlEncoder().withoutPadding();
        String header = b64.encodeToString(("{\"alg\":\"ES256\",\"kid\":\"" + keyId + "\"}").getBytes(StandardCharsets.UTF_8));
        long now = Instant.now().getEpochSecond();
        String claims = b64.encodeToString(("{\"iss\":\"" + teamId + "\",\"iat\":" + now + "}").getBytes(StandardCharsets.UTF_8));
        String signingInput = header + "." + claims;
        Signature signer = Signature.getInstance("SHA256withECDSAinP1363Format"); // r||s, as JWT expects
        signer.initSign(key);
        signer.update(signingInput.getBytes(StandardCharsets.UTF_8));
        jwt = signingInput + "." + b64.encodeToString(signer.sign());
        jwtMadeAt = Instant.now();
        return jwt;
    }

    /** the .p8 file's text (with or without the BEGIN/END lines; "\n" written out is fine) */
    static PrivateKey parseKey(String pem) {
        if (pem == null || pem.isBlank()) return null;
        try {
            String base64 = pem.replace("\\n", "\n")
                    .replace("-----BEGIN PRIVATE KEY-----", "")
                    .replace("-----END PRIVATE KEY-----", "")
                    .replaceAll("\\s", "");
            return KeyFactory.getInstance("EC").generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(base64)));
        } catch (Exception e) {
            log.error("APNS_PRIVATE_KEY isn't a valid .p8 key ({})", e.toString());
            return null;
        }
    }

    private static String env(Dotenv dotenv, String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) value = dotenv.get(name);
        return value == null || value.isBlank() ? null : value.strip();
    }
}
