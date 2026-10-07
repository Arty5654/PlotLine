package com.plotline.backend.service;

import java.util.ArrayList;
import java.util.List;

import org.springframework.stereotype.Component;

import com.google.api.client.googleapis.auth.oauth2.GoogleIdToken;
import com.google.api.client.googleapis.auth.oauth2.GoogleIdTokenVerifier;
import com.google.api.client.http.javanet.NetHttpTransport;
import com.google.api.client.json.jackson2.JacksonFactory;

import io.github.cdimascio.dotenv.Dotenv;

/**
 * Checks the ID token Google Sign-In gives the app: Google's signature, issuer, and that it was
 * issued for one of our client IDs (GOOGLE_CLIENT_ID = server/web client, GOOGLE_IOS_CLIENT_ID).
 */
@Component
public class GoogleTokenVerifier {

    public record GoogleIdentity(String subject, String email) { }

    private final GoogleIdTokenVerifier verifier;

    public GoogleTokenVerifier() {
        Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();
        List<String> audience = new ArrayList<>();
        for (String key : List.of("GOOGLE_CLIENT_ID", "GOOGLE_IOS_CLIENT_ID")) {
            String value = dotenv.get(key);
            if (value != null && !value.isBlank()) audience.add(value);
        }
        this.verifier = new GoogleIdTokenVerifier.Builder(new NetHttpTransport(), JacksonFactory.getDefaultInstance())
                .setAudience(audience)
                .setIssuer("https://accounts.google.com")
                .build();
    }

    /** The Google account behind a valid token, or null if the token isn't valid. */
    public GoogleIdentity verify(String idToken) throws Exception {
        if (idToken == null || idToken.isBlank()) return null;
        GoogleIdToken token = verifier.verify(idToken);
        if (token == null) return null;
        GoogleIdToken.Payload payload = token.getPayload();
        return new GoogleIdentity(payload.getSubject(), payload.getEmail());
    }
}
