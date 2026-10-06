package com.plotline.backend.service;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.S3UserRecord;
import com.plotline.backend.testsupport.InMemoryS3Client;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.bcrypt.BCrypt;

import java.util.Date;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Hermetic tests for password/Google sign-in rules and login tokens, against the in-memory S3 double.
 */
class AuthServiceTest {

    private static final String GOOGLE_SUB = "109876543210987654321";

    private InMemoryS3Client s3;
    private AuthService authService;
    private final ObjectMapper objectMapper = new ObjectMapper();

    @BeforeEach
    void setUp() {
        s3 = new InMemoryS3Client();
        authService = new AuthService(s3, null, "test-jwt-secret");
    }

    private S3UserRecord record(String username) throws Exception {
        return objectMapper.readValue(
                s3.getObjectAsBytes(b -> b.bucket("plotline-database-bucket")
                        .key("users/" + username + "/account.json")).asByteArray(),
                S3UserRecord.class);
    }

    // How Google accounts were stored before the fix: the Google user id hashed as the password
    private void createLegacyGoogleUser(String username) throws Exception {
        S3UserRecord legacy = new S3UserRecord(username, username, "", username + "@gmail.com",
                BCrypt.hashpw(GOOGLE_SUB, BCrypt.gensalt()), true, true);
        s3.putRaw("users/" + username + "/account.json", objectMapper.writeValueAsBytes(legacy));
    }

    // ── Google password loophole ───────────────────────────────────────────────

    @Test
    @DisplayName("Legacy Google account can't be signed into with its Google id as a password")
    void legacyGoogleIdIsNotAPassword() throws Exception {
        createLegacyGoogleUser("googler");

        assertThat(authService.userLogin("googler", GOOGLE_SUB)).isEqualTo("Please sign in with Google!");
    }

    @Test
    @DisplayName("New Google accounts store the Google id separately and have no usable password")
    void newGoogleAccountStoresSub() throws Exception {
        assertThat(authService.createGoogleUser("me@gmail.com", "googler", "Googler", GOOGLE_SUB)).isTrue();

        S3UserRecord record = record("googler");
        assertThat(record.getIsGoogle()).isTrue();
        assertThat(record.getGoogleSub()).isEqualTo(GOOGLE_SUB);
        assertThat(BCrypt.checkpw(GOOGLE_SUB, record.getPassword())).isFalse();
        assertThat(authService.userLogin("googler", GOOGLE_SUB)).isEqualTo("Please sign in with Google!");
    }

    @Test
    @DisplayName("Google sign-in matches on the stored Google id")
    void googleLoginMatchesSub() {
        authService.createGoogleUser("me@gmail.com", "googler", "Googler", GOOGLE_SUB);

        assertThat(authService.googleLogin("googler", GOOGLE_SUB)).isEqualTo("true"); // no phone step for Google
        assertThat(authService.googleLogin("googler", "someone-else")).isEqualTo("Google account does not match");
    }

    @Test
    @DisplayName("Legacy Google account migrates to a stored Google id on its next Google sign-in")
    void legacyGoogleAccountMigrates() throws Exception {
        createLegacyGoogleUser("googler");

        assertThat(authService.googleLogin("googler", GOOGLE_SUB)).isEqualTo("true");

        S3UserRecord migrated = record("googler");
        assertThat(migrated.getGoogleSub()).isEqualTo(GOOGLE_SUB);
        assertThat(BCrypt.checkpw(GOOGLE_SUB, migrated.getPassword())).isFalse();
        // still signs in afterwards, now through the stored id
        assertThat(authService.googleLogin("googler", GOOGLE_SUB)).isEqualTo("true");
    }

    @Test
    @DisplayName("Legacy Google account rejects a different Google id")
    void legacyGoogleAccountRejectsWrongSub() throws Exception {
        createLegacyGoogleUser("googler");

        assertThat(authService.googleLogin("googler", "someone-else")).isEqualTo("Google account does not match");
        assertThat(record("googler").getGoogleSub()).isNull();
    }

    @Test
    @DisplayName("Google sign-in can't be used to get into a password account")
    void googleLoginRejectsPasswordAccount() {
        authService.createUser("555", "me@gmail.com", "plain", "plain", "Password1", false);

        assertThat(authService.googleLogin("plain", "Password1")).isEqualTo("Non-Google account for this username exists");
    }

    @Test
    @DisplayName("Only password accounts need phone verification; Google and Apple accounts skip it")
    void phoneVerificationOnlyForPasswordAccounts() throws Exception {
        authService.createUser("555", "me@mail.com", "plain", "plain", "Password1", false);
        authService.createGoogleUser("g@gmail.com", "googler", "googler", GOOGLE_SUB);
        authService.createAppleUser("a@icloud.com", "appler", "appler", "001.apple");

        assertThat(authService.needsPhoneVerification("plain")).isTrue();
        assertThat(authService.userLogin("plain", "Password1")).isEqualTo("Needs Verification");
        assertThat(authService.needsPhoneVerification("googler")).isFalse();
        assertThat(authService.needsPhoneVerification("appler")).isFalse();

        // once the password account verifies its phone, it's done too
        authService.updateUserRecord("plain", r -> r.setIsVerified(true));
        assertThat(authService.needsPhoneVerification("plain")).isFalse();
    }

    // ── Password changes ───────────────────────────────────────────────────────

    @Test
    @DisplayName("Google and Apple accounts can't change or set a password")
    void socialAccountsCantChangePassword() throws Exception {
        createLegacyGoogleUser("googler");
        authService.createAppleUser("me@icloud.com", "appler", "appler", "001.apple");

        assertThat(authService.changeUserPassword("googler", GOOGLE_SUB, "NewPass1", ""))
                .isEqualTo("This account signs in with Google and doesn't have a password.");
        assertThat(authService.changeUserPassword("appler", "anything", "NewPass1", ""))
                .isEqualTo("This account signs in with Apple and doesn't have a password.");
    }

    @Test
    @DisplayName("Password change is saved to the real account even when the username is typed in different case")
    void changePasswordUsesStoredKey() {
        authService.createUser("555", "me@mail.com", "Mixed", "Mixed", "Password1", false);

        assertThat(authService.changeUserPassword("MIXED", "Password1", "NewPass1", "")).isEqualTo("success");

        assertThat(s3.contains("users/MIXED/account.json")).isFalse();
        assertThat(authService.userLogin("mixed", "NewPass1")).isEqualTo("Needs Verification");
    }

    @Test
    @DisplayName("Normal password sign-in still works")
    void passwordLoginStillWorks() {
        authService.createUser("555", "me@mail.com", "plain", "plain", "Password1", false);

        assertThat(authService.userLogin("plain", "Password1")).isEqualTo("Needs Verification");
        assertThat(authService.userLogin("plain", "wrong")).isEqualTo("Incorrect Password");
    }

    // ── Signed-in sessions ─────────────────────────────────────────────────────

    @Test
    @DisplayName("A fresh login token signs its account in")
    void sessionForNewToken() {
        authService.createUser("555", "me@mail.com", "Plain", "Plain", "Password1", false);

        assertThat(authService.authenticatedUsername(authService.generateToken("Plain"))).isEqualTo("plain");
    }

    @Test
    @DisplayName("Tokens issued before the fix were born expired and no longer work")
    void oldBrokenTokensRejected() {
        authService.createUser("555", "me@mail.com", "plain", "plain", "Password1", false);
        long now = System.currentTimeMillis();
        // what the old int-overflow code produced: expiry ~20 days before issue time
        String oldToken = JWT.create().withIssuer("PlotLineApp").withClaim("username", "plain")
                .withIssuedAt(new Date(now - 60_000))
                .withExpiresAt(new Date(now - 60_000 + (int) (1000L * 60 * 60 * 24 * 30)))
                .sign(Algorithm.HMAC256("test-jwt-secret"));

        assertThat(authService.authenticatedUsername(oldToken)).isNull();
    }

    @Test
    @DisplayName("A deleted account's token stops working")
    void deletedAccountTokenRejected() {
        authService.createUser("555", "me@mail.com", "plain", "plain", "Password1", false);
        String token = authService.generateToken("plain");
        assertThat(authService.authenticatedUsername(token)).isEqualTo("plain");

        s3.deleteRaw("users/plain/account.json");
        authService.evictAccountCache("plain");

        assertThat(authService.authenticatedUsername(token)).isNull();
    }

    @Test
    @DisplayName("An old token can't get into a new account that reused the same username")
    void tokenFromBeforeAccountCreationRejected() throws Exception {
        authService.createUser("555", "me@mail.com", "plain", "plain", "Password1", false);
        long now = System.currentTimeMillis();
        String oldToken = JWT.create().withIssuer("PlotLineApp").withClaim("username", "plain")
                .withIssuedAt(new Date(now - 3_600_000))
                .withExpiresAt(new Date(now + 3_600_000))
                .sign(Algorithm.HMAC256("test-jwt-secret"));

        assertThat(authService.authenticatedUsername(oldToken)).isNull();
    }

    @Test
    @DisplayName("Accounts from before creation times were recorded still accept valid tokens")
    void legacyAccountWithoutCreatedAt() throws Exception {
        createLegacyGoogleUser("googler");

        assertThat(authService.authenticatedUsername(authService.generateToken("googler"))).isEqualTo("googler");
    }

    // ── Login tokens ───────────────────────────────────────────────────────────

    @Test
    @DisplayName("Login tokens we issue are accepted; forged or expired ones are not")
    void usernameFromToken() {
        assertThat(authService.usernameFromToken(authService.generateToken("Someone"))).isEqualTo("someone");

        String forged = JWT.create().withIssuer("PlotLineApp").withClaim("username", "victim")
                .sign(Algorithm.HMAC256("not-our-secret"));
        assertThat(authService.usernameFromToken(forged)).isNull();

        String expired = JWT.create().withIssuer("PlotLineApp").withClaim("username", "someone")
                .withExpiresAt(new Date(System.currentTimeMillis() - 60_000))
                .sign(Algorithm.HMAC256("test-jwt-secret"));
        assertThat(authService.usernameFromToken(expired)).isNull();

        assertThat(authService.usernameFromToken(null)).isNull();
        assertThat(authService.usernameFromToken("garbage")).isNull();
    }
}
