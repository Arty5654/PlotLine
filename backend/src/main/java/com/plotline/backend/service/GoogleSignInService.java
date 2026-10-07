package com.plotline.backend.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.springframework.stereotype.Service;

import com.plotline.backend.dto.AuthResponse;
import com.plotline.backend.dto.GoogleSigninRequest;
import com.plotline.backend.service.GoogleTokenVerifier.GoogleIdentity;

/**
 * Google sign-in. Returning users are recognized by their Google account (through their email);
 * new users choose their own username, like Sign in with Apple:
 *   1. returning Google user          -> signed in
 *   2. new user, no username sent yet -> "Username Required" with a suggestion from their email
 *   3. new user + chosen username     -> account created
 */
@Service
public class GoogleSignInService {
    private static final Logger log = LoggerFactory.getLogger(GoogleSignInService.class);


    public static final String USERNAME_REQUIRED = "Username Required";

    private final AuthService authService;
    private final GoogleTokenVerifier verifier;

    public GoogleSignInService(AuthService authService, GoogleTokenVerifier verifier) {
        this.authService = authService;
        this.verifier = verifier;
    }

    public AuthResponse signIn(GoogleSigninRequest request) {
        GoogleIdentity identity;
        try {
            identity = verifier.verify(request.getIdToken());
        } catch (Exception e) {
            identity = null;
        }
        if (identity == null) {
            return fail("Invalid Google ID Token");
        }

        String email = authService.normalizeEmail(identity.email());
        if (email.isBlank() || !email.contains("@")) {
            return fail("Email not available from Google");
        }

        try {
            // returning user: the account that owns this email
            String owner = authService.usernameForEmail(email);
            if (owner != null && authService.userExists(owner)) {
                if (authService.googleUser(owner)) {
                    return signIn(owner, identity.subject(), true);
                }
                if (authService.appleUser(owner)) {
                    return fail("This email is linked to a Sign in with Apple account. Please sign in with Apple.");
                }
                return fail("An account with this email already exists. Sign in with your username and password.");
            }

            // older Google accounts used the email prefix as their username
            String legacyUsername = authService.normalizeUsername(email.substring(0, email.indexOf('@')));
            if (!legacyUsername.isBlank() && authService.userExists(legacyUsername) && authService.googleUser(legacyUsername)) {
                AuthResponse legacy = signIn(legacyUsername, identity.subject(), false);
                if (legacy != null) return legacy;
                // same prefix, different Google account: treat as a new user below
            }

            // new user: they choose their username (suggested from their email)
            String chosen = request.getUsername();
            if (chosen == null || chosen.isBlank()) {
                return new AuthResponse(false, null, USERNAME_REQUIRED, authService.suggestUsername(email));
            }
            String displayUsername = chosen.trim();
            if (!AuthService.isValidUsername(displayUsername)) {
                return fail(AuthService.USERNAME_RULES);
            }
            if (authService.userExists(displayUsername)) {
                return fail("Username already taken");
            }
            if (!authService.createGoogleUser(email, displayUsername, displayUsername, identity.subject())) {
                return fail("Could not create user");
            }
            log.debug("Google user CREATED");
            return new AuthResponse(true, authService.generateToken(displayUsername), null, displayUsername);

        } catch (Exception e) {
            log.error("signIn failed", e);
            return fail("Server Error");
        }
    }

    // signs an existing Google account in; on a Google-ID mismatch returns an error,
    // or null when mismatchIsError is false (so the caller can try something else)
    private AuthResponse signIn(String username, String googleSub, boolean mismatchIsError) {
        String result = authService.googleLogin(username, googleSub);
        if (!result.equals("true") && !result.equals("Needs Verification")) {
            return mismatchIsError ? fail(result) : null;
        }
        String status = result.equals("Needs Verification") ? "Needs Verification" : null;
        return new AuthResponse(true, authService.generateToken(username), status, authService.getDisplayUsername(username));
    }

    private static AuthResponse fail(String message) {
        return new AuthResponse(false, null, message);
    }
}
