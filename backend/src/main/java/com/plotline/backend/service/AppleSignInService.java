package com.plotline.backend.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;

import org.springframework.stereotype.Service;

import com.auth0.jwt.exceptions.JWTVerificationException;
import com.auth0.jwt.exceptions.TokenExpiredException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.AppleSigninRequest;
import com.plotline.backend.dto.AuthResponse;
import com.plotline.backend.dto.S3UserRecord;
import com.plotline.backend.service.AppleIdTokenVerifier.AppleIdentity;

import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

/**
 * Sign in with Apple. Apple accounts are tracked by Apple's stable user id ("sub"),
 * stored at apple-users/{sub}.json -> { "username": ... }.
 *
 * The app may need up to three calls with the same identity token:
 *   1. returning Apple user            -> signed in
 *   2. new, email matches an account   -> "Link Required", resend with that account's password
 *   3. new, no matching account        -> "Username Required", resend with a chosen username
 */
@Service
public class AppleSignInService {
    private static final Logger log = LoggerFactory.getLogger(AppleSignInService.class);


    public static final String USERNAME_REQUIRED = "Username Required";
    public static final String LINK_REQUIRED = "Link Required";
    private static final String NEEDS_VERIFICATION = "Needs Verification";

    private final AuthService authService;
    private final AppleIdTokenVerifier verifier;
    private final S3Client s3Client;
    private final String bucketName = "plotline-database-bucket";
    private final ObjectMapper objectMapper = new ObjectMapper();

    public AppleSignInService(AuthService authService, AppleIdTokenVerifier verifier, S3Client s3Client) {
        this.authService = authService;
        this.verifier = verifier;
        this.s3Client = s3Client;
    }

    public AuthResponse signIn(AppleSigninRequest request) {
        AppleIdentity identity;
        try {
            identity = verifier.verify(request.getIdentityToken(), request.getRawNonce());
        } catch (TokenExpiredException e) {
            return fail("Apple sign-in expired. Please try again.");
        } catch (JWTVerificationException e) {
            return fail("Invalid Apple ID Token");
        }

        try {
            // returning Apple user (the account must still point back at this Apple ID)
            String linkedUsername = linkedUsername(identity.subject());
            if (linkedUsername != null) {
                S3UserRecord linkedRecord = authService.getUserRecord(linkedUsername);
                if (linkedRecord != null && identity.subject().equals(linkedRecord.getAppleSub())) {
                    return signedIn(linkedUsername);
                }
            }

            String email = authService.normalizeEmail(identity.email());
            if (email.isBlank()) {
                return fail("Email not available from Apple");
            }

            String owner = authService.usernameForEmail(email);
            if (owner != null && authService.userExists(owner)) {
                return linkExistingAccount(identity, owner, request.getLinkPassword());
            }

            return createAccount(identity, email, request.getUsername());

        } catch (Exception e) {
            log.error("signIn failed", e);
            return fail("Server Error");
        }
    }

    // the email already belongs to an account: only link once the user proves they own it
    private AuthResponse linkExistingAccount(AppleIdentity identity, String owner, String password) throws Exception {
        if (authService.googleUser(owner)) {
            return fail("This email is linked to a Google account. Please sign in with Google.");
        }
        if (authService.appleUser(owner)) {
            // created with a different Apple ID, has no usable password to link with
            return fail("Email already exists");
        }

        if (password == null || password.isEmpty()) {
            return new AuthResponse(false, null, LINK_REQUIRED, authService.getDisplayUsername(owner));
        }

        String loginResult = authService.userLogin(owner, password);
        if (!loginResult.equals("true") && !loginResult.equals(NEEDS_VERIFICATION)) {
            return fail(loginResult);
        }

        authService.updateUserRecord(owner, record -> record.setAppleSub(identity.subject()));
        saveLink(identity.subject(), owner);
        log.debug("Apple user LINKED");
        return signedIn(owner);
    }

    private AuthResponse createAccount(AppleIdentity identity, String email, String requestedUsername) throws Exception {
        if (requestedUsername == null || requestedUsername.isBlank()) {
            return new AuthResponse(false, null, USERNAME_REQUIRED);
        }

        String displayUsername = requestedUsername.trim();
        String username = authService.normalizeUsername(displayUsername);
        if (!AuthService.isValidUsername(displayUsername)) {
            return fail(AuthService.USERNAME_RULES);
        }
        if (authService.userExists(username)) {
            return fail("Username already taken");
        }

        boolean created = authService.createAppleUser(email, username, displayUsername, identity.subject());
        if (!created) {
            return fail("Could not create user");
        }
        saveLink(identity.subject(), username);

        log.debug("Apple user CREATED");

        String token = authService.generateToken(username);
        return new AuthResponse(true, token, null, displayUsername); // Apple already verified them
    }

    private AuthResponse signedIn(String username) {
        String token = authService.generateToken(username);
        String displayUsername = authService.getDisplayUsername(username);
        String status = authService.needsPhoneVerification(username) ? NEEDS_VERIFICATION : null;
        return new AuthResponse(true, token, status, displayUsername);
    }

    private AuthResponse fail(String message) {
        return new AuthResponse(false, null, message);
    }

    private String appleUserKey(String subject) {
        return "apple-users/" + subject + ".json";
    }

    private String linkedUsername(String subject) {
        try {
            GetObjectRequest getRequest = GetObjectRequest.builder()
                    .bucket(bucketName)
                    .key(appleUserKey(subject))
                    .build();
            ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
            Map<?, ?> link = objectMapper.readValue(objectBytes.asByteArray(), Map.class);
            Object username = link.get("username");
            return username instanceof String ? (String) username : null;
        } catch (Exception e) {
            return null;
        }
    }

    // called when an account is deleted
    public void deleteLink(String subject) {
        s3Client.deleteObject(DeleteObjectRequest.builder().bucket(bucketName).key(appleUserKey(subject)).build());
    }

    private void saveLink(String subject, String username) throws Exception {
        String json = objectMapper.writeValueAsString(Map.of("username", authService.normalizeUsername(username)));
        PutObjectRequest putRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(appleUserKey(subject))
                .contentType("application/json")
                .build();
        s3Client.putObject(putRequest, RequestBody.fromString(json));
    }
}
