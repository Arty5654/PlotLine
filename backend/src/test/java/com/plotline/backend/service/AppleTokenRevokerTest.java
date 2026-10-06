package com.plotline.backend.service;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.interfaces.DecodedJWT;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/** Tests the Apple client secret and token calls without talking to Apple. */
class AppleTokenRevokerTest {

    private static KeyPair ecKeyPair() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        return generator.generateKeyPair();
    }

    // same shape as the .p8 file Apple gives you, with "\n" escapes as it would sit in an env var
    private static String p8(KeyPair keys) {
        String base64 = Base64.getEncoder().encodeToString(keys.getPrivate().getEncoded());
        return "-----BEGIN PRIVATE KEY-----\\n" + base64.replaceAll("(.{64})", "$1\\\\n") + "\\n-----END PRIVATE KEY-----";
    }

    @Test
    @DisplayName("Client secret is an ES256 JWT signed with the .p8 key, in the shape Apple expects")
    void clientSecret() throws Exception {
        KeyPair keys = ecKeyPair();
        AppleTokenRevoker revoker = new AppleTokenRevoker("TEAM123", "KEY456", p8(keys), "com.test.PlotLine");

        DecodedJWT secret = JWT.require(Algorithm.ECDSA256((ECPublicKey) keys.getPublic(), null))
                .build()
                .verify(revoker.clientSecret());

        assertThat(secret.getKeyId()).isEqualTo("KEY456");
        assertThat(secret.getIssuer()).isEqualTo("TEAM123");
        assertThat(secret.getSubject()).isEqualTo("com.test.PlotLine");
        assertThat(secret.getAudience()).containsExactly("https://appleid.apple.com");
        assertThat(secret.getExpiresAt()).isAfter(secret.getIssuedAt());
    }

    @Test
    @DisplayName("Exchanging a code returns the Apple user id and refresh token, then revoke sends it back")
    void exchangeAndRevoke() throws Exception {
        List<Map<String, String>> calls = new ArrayList<>();
        List<String> urls = new ArrayList<>();
        String idToken = JWT.create().withSubject("001.apple.user").sign(Algorithm.HMAC256("x"));

        AppleTokenRevoker revoker = new AppleTokenRevoker("TEAM123", "KEY456", p8(ecKeyPair()), "com.test.PlotLine") {
            @Override
            String post(String url, Map<String, String> form) {
                urls.add(url);
                calls.add(form);
                return "{\"refresh_token\":\"refresh-abc\",\"id_token\":\"" + idToken + "\"}";
            }
        };

        AppleTokenRevoker.AppleTokens tokens = revoker.exchangeCode("one-time-code");
        revoker.revoke(tokens.refreshToken());

        assertThat(tokens.subject()).isEqualTo("001.apple.user");
        assertThat(tokens.refreshToken()).isEqualTo("refresh-abc");
        assertThat(urls).containsExactly("https://appleid.apple.com/auth/token", "https://appleid.apple.com/auth/revoke");
        assertThat(calls.get(0)).containsEntry("code", "one-time-code").containsEntry("grant_type", "authorization_code")
                .containsEntry("client_id", "com.test.PlotLine");
        assertThat(calls.get(1)).containsEntry("token", "refresh-abc").containsEntry("token_type_hint", "refresh_token");
    }

    @Test
    @DisplayName("Not configured until all three Apple key settings are present")
    void configuration() {
        assertThat(new AppleTokenRevoker("TEAM", "KEY", "pem", "id").isConfigured()).isTrue();
        assertThat(new AppleTokenRevoker("TEAM", null, "pem", "id").isConfigured()).isFalse();
        assertThat(new AppleTokenRevoker("", "KEY", "pem", "id").isConfigured()).isFalse();
    }
}
