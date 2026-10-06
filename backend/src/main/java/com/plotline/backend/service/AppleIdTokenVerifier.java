package com.plotline.backend.service;

import java.math.BigInteger;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.RSAPublicKeySpec;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.Map;
import java.util.function.Function;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.exceptions.JWTVerificationException;
import com.auth0.jwt.interfaces.Claim;
import com.auth0.jwt.interfaces.DecodedJWT;
import com.auth0.jwt.interfaces.RSAKeyProvider;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import io.github.cdimascio.dotenv.Dotenv;

/**
 * Verifies the identity token that Sign in with Apple hands the iOS app.
 * Checks Apple's signature (public keys from Apple's JWKS endpoint), issuer,
 * audience (our bundle id), expiry, and the nonce the app generated.
 */
@Component
public class AppleIdTokenVerifier {

    public record AppleIdentity(String subject, String email) { }

    private static final String ISSUER = "https://appleid.apple.com";
    private static final URI KEYS_URI = URI.create("https://appleid.apple.com/auth/keys");
    private static final String DEFAULT_BUNDLE_ID = "com.ArteomAvetissian.PlotLine";
    // don't hammer Apple when someone sends a token with a bogus key id
    private static final Duration MIN_REFRESH_INTERVAL = Duration.ofMinutes(1);

    private final String audience;
    private final Function<String, RSAPublicKey> keyLookup;

    private final HttpClient httpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    private final ObjectMapper objectMapper = new ObjectMapper();
    private Map<String, RSAPublicKey> cachedKeys = Map.of();
    private Instant lastFetch = Instant.EPOCH;

    @Autowired
    public AppleIdTokenVerifier() {
        Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();
        String bundleId = dotenv.get("IOS_BUNDLE_ID");
        this.audience = (bundleId == null || bundleId.isBlank()) ? DEFAULT_BUNDLE_ID : bundleId;
        this.keyLookup = this::appleKey;
    }

    // for tests: supply our own signing keys instead of fetching Apple's
    AppleIdTokenVerifier(String audience, Function<String, RSAPublicKey> keyLookup) {
        this.audience = audience;
        this.keyLookup = keyLookup;
    }

    public AppleIdentity verify(String identityToken, String rawNonce) {
        if (identityToken == null || identityToken.isBlank() || rawNonce == null || rawNonce.isBlank()) {
            throw new JWTVerificationException("Missing identity token or nonce");
        }

        RSAKeyProvider keyProvider = new RSAKeyProvider() {
            @Override public RSAPublicKey getPublicKeyById(String keyId) { return keyLookup.apply(keyId); }
            @Override public RSAPrivateKey getPrivateKey() { return null; }
            @Override public String getPrivateKeyId() { return null; }
        };

        DecodedJWT jwt = JWT.require(Algorithm.RSA256(keyProvider))
                .withIssuer(ISSUER)
                .withAudience(audience)
                .acceptLeeway(60)
                .build()
                .verify(identityToken);

        // the app puts sha256(rawNonce) in the request, Apple echoes it back in the token
        String expectedNonce = sha256Hex(rawNonce);
        String tokenNonce = jwt.getClaim("nonce").asString();
        if (tokenNonce == null || !MessageDigest.isEqual(
                expectedNonce.getBytes(StandardCharsets.UTF_8), tokenNonce.getBytes(StandardCharsets.UTF_8))) {
            throw new JWTVerificationException("Nonce mismatch");
        }

        // subject becomes part of an S3 key, so only accept Apple's documented format
        String subject = jwt.getSubject();
        if (subject == null || !subject.matches("^[A-Za-z0-9._-]{1,128}$")) {
            throw new JWTVerificationException("Invalid subject");
        }

        String email = jwt.getClaim("email").asString();
        if (!isTrue(jwt.getClaim("email_verified"))) {
            email = null;
        }

        return new AppleIdentity(subject, email);
    }

    // Apple has sent this claim as both a boolean and the string "true"
    private static boolean isTrue(Claim claim) {
        Boolean asBool = claim.asBoolean();
        if (asBool != null) return asBool;
        return "true".equalsIgnoreCase(claim.asString());
    }

    static String sha256Hex(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private synchronized RSAPublicKey appleKey(String keyId) {
        RSAPublicKey key = cachedKeys.get(keyId);
        if (key == null && Duration.between(lastFetch, Instant.now()).compareTo(MIN_REFRESH_INTERVAL) >= 0) {
            lastFetch = Instant.now();
            try {
                cachedKeys = fetchAppleKeys();
            } catch (Exception e) {
                System.out.println("Failed to fetch Apple public keys: " + e.getMessage());
            }
            key = cachedKeys.get(keyId);
        }
        return key;
    }

    private Map<String, RSAPublicKey> fetchAppleKeys() throws Exception {
        HttpRequest request = HttpRequest.newBuilder(KEYS_URI).timeout(Duration.ofSeconds(5)).GET().build();
        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200) {
            throw new IllegalStateException("Apple keys endpoint returned " + response.statusCode());
        }

        Map<String, RSAPublicKey> keys = new HashMap<>();
        KeyFactory keyFactory = KeyFactory.getInstance("RSA");
        Base64.Decoder decoder = Base64.getUrlDecoder();
        for (JsonNode jwk : objectMapper.readTree(response.body()).path("keys")) {
            if (!"RSA".equals(jwk.path("kty").asText())) continue;
            BigInteger modulus = new BigInteger(1, decoder.decode(jwk.path("n").asText()));
            BigInteger exponent = new BigInteger(1, decoder.decode(jwk.path("e").asText()));
            keys.put(jwk.path("kid").asText(),
                     (RSAPublicKey) keyFactory.generatePublic(new RSAPublicKeySpec(modulus, exponent)));
        }
        return keys;
    }
}
