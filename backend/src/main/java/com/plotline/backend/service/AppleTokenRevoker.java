package com.plotline.backend.service;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.interfaces.ECPrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import io.github.cdimascio.dotenv.Dotenv;

/**
 * Revokes a user's Sign in with Apple tokens when they delete their account (App Store rule 5.1.1(v)).
 * The app sends a fresh one-time authorization code; we trade it for a refresh token and revoke that.
 *
 * Needs a Sign in with Apple key from the Apple Developer portal:
 *   APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (contents of the .p8 file)
 */
@Component
public class AppleTokenRevoker {

    public record AppleTokens(String subject, String refreshToken) { }

    private static final String APPLE = "https://appleid.apple.com";
    private static final String DEFAULT_BUNDLE_ID = "com.ArteomAvetissian.PlotLine";

    private final String teamId;
    private final String keyId;
    private final String privateKeyPem;
    private final String clientId;

    private final HttpClient httpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Autowired
    public AppleTokenRevoker() {
        Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();
        this.teamId = dotenv.get("APPLE_TEAM_ID");
        this.keyId = dotenv.get("APPLE_KEY_ID");
        this.privateKeyPem = dotenv.get("APPLE_PRIVATE_KEY");
        String bundleId = dotenv.get("IOS_BUNDLE_ID");
        this.clientId = (bundleId == null || bundleId.isBlank()) ? DEFAULT_BUNDLE_ID : bundleId;
    }

    AppleTokenRevoker(String teamId, String keyId, String privateKeyPem, String clientId) {
        this.teamId = teamId;
        this.keyId = keyId;
        this.privateKeyPem = privateKeyPem;
        this.clientId = clientId;
    }

    public boolean isConfigured() {
        return notBlank(teamId) && notBlank(keyId) && notBlank(privateKeyPem);
    }

    // trade the app's one-time authorization code for the user's Apple tokens
    public AppleTokens exchangeCode(String authorizationCode) throws Exception {
        Map<String, String> form = new LinkedHashMap<>();
        form.put("client_id", clientId);
        form.put("client_secret", clientSecret());
        form.put("code", authorizationCode);
        form.put("grant_type", "authorization_code");

        JsonNode body = objectMapper.readTree(post(APPLE + "/auth/token", form));
        String refreshToken = body.path("refresh_token").asText(null);
        String idToken = body.path("id_token").asText(null);
        if (refreshToken == null || idToken == null) {
            throw new IllegalStateException("Apple token response missing tokens");
        }
        // came straight from Apple over TLS in reply to our signed request, so decoding is enough
        return new AppleTokens(JWT.decode(idToken).getSubject(), refreshToken);
    }

    public void revoke(String refreshToken) throws Exception {
        Map<String, String> form = new LinkedHashMap<>();
        form.put("client_id", clientId);
        form.put("client_secret", clientSecret());
        form.put("token", refreshToken);
        form.put("token_type_hint", "refresh_token");
        post(APPLE + "/auth/revoke", form);
    }

    // returns the response body, throws unless Apple answered 200
    String post(String url, Map<String, String> form) throws Exception {
        String encoded = form.entrySet().stream()
                .map(e -> URLEncoder.encode(e.getKey(), StandardCharsets.UTF_8) + "="
                        + URLEncoder.encode(e.getValue(), StandardCharsets.UTF_8))
                .collect(Collectors.joining("&"));
        HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                .timeout(Duration.ofSeconds(10))
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString(encoded))
                .build();
        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200) {
            throw new IllegalStateException("Apple " + url + " returned " + response.statusCode() + ": " + response.body());
        }
        return response.body();
    }

    // Apple's "client secret" is a short-lived JWT signed with our Sign in with Apple key
    String clientSecret() throws Exception {
        Instant now = Instant.now();
        return JWT.create()
                .withKeyId(keyId)
                .withIssuer(teamId)
                .withIssuedAt(Date.from(now))
                .withExpiresAt(Date.from(now.plus(Duration.ofMinutes(5))))
                .withAudience(APPLE)
                .withSubject(clientId)
                .sign(Algorithm.ECDSA256(null, privateKey()));
    }

    private ECPrivateKey privateKey() throws Exception {
        // env vars often carry the .p8 with literal "\n" instead of real newlines
        String base64 = privateKeyPem
                .replace("\\n", "\n")
                .replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replaceAll("\\s", "");
        byte[] der = Base64.getDecoder().decode(base64);
        return (ECPrivateKey) KeyFactory.getInstance("EC").generatePrivate(new PKCS8EncodedKeySpec(der));
    }

    private static boolean notBlank(String value) {
        return value != null && !value.isBlank();
    }
}
