package com.plotline.backend.service;

import com.auth0.jwt.JWT;
import com.auth0.jwt.JWTCreator;
import com.auth0.jwt.algorithms.Algorithm;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.AppleSigninRequest;
import com.plotline.backend.dto.AuthResponse;
import com.plotline.backend.dto.S3UserRecord;
import com.plotline.backend.testsupport.InMemoryS3Client;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.function.Consumer;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Hermetic tests for Sign in with Apple. Tokens are signed with a locally generated RSA key
 * that the verifier is told to trust, and accounts live in the in-memory S3 double.
 */
class AppleSignInServiceTest {

    private static final String AUDIENCE = "com.test.PlotLine";
    private static final String KEY_ID = "test-key";
    private static final String NONCE = "raw-nonce-123";
    private static final String SUBJECT = "001234.abcdef0123456789.1234";

    private static KeyPair appleKeys;
    private static KeyPair otherKeys;

    private InMemoryS3Client s3;
    private AuthService authService;
    private AppleSignInService service;
    private final ObjectMapper objectMapper = new ObjectMapper();

    @BeforeEach
    void setUp() throws Exception {
        if (appleKeys == null) {
            KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
            generator.initialize(2048);
            appleKeys = generator.generateKeyPair();
            otherKeys = generator.generateKeyPair();
        }
        s3 = new InMemoryS3Client();
        authService = new AuthService(s3, null, "test-jwt-secret");
        AppleIdTokenVerifier verifier = new AppleIdTokenVerifier(AUDIENCE,
                kid -> KEY_ID.equals(kid) ? (RSAPublicKey) appleKeys.getPublic() : null);
        service = new AppleSignInService(authService, verifier, s3);
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private String token(String email, Consumer<JWTCreator.Builder> customize) {
        JWTCreator.Builder builder = JWT.create()
                .withKeyId(KEY_ID)
                .withIssuer("https://appleid.apple.com")
                .withAudience(AUDIENCE)
                .withSubject(SUBJECT)
                .withIssuedAt(new Date())
                .withExpiresAt(Date.from(Instant.now().plus(10, ChronoUnit.MINUTES)))
                .withClaim("nonce", AppleIdTokenVerifier.sha256Hex(NONCE))
                .withClaim("email_verified", true);
        if (email != null) builder.withClaim("email", email);
        customize.accept(builder);
        return builder.sign(Algorithm.RSA256(null, (RSAPrivateKey) appleKeys.getPrivate()));
    }

    private String token(String email) {
        return token(email, b -> { });
    }

    private AuthResponse signIn(String token, String username, String linkPassword) {
        return service.signIn(new AppleSigninRequest(token, NONCE, username, linkPassword));
    }

    private S3UserRecord record(String username) throws Exception {
        return objectMapper.readValue(
                s3.getObjectAsBytes(b -> b.bucket("plotline-database-bucket")
                        .key("users/" + username + "/account.json")).asByteArray(),
                S3UserRecord.class);
    }

    private void markVerified(String username) throws Exception {
        S3UserRecord record = record(username);
        record.setIsVerified(true);
        s3.putRaw("users/" + username + "/account.json", objectMapper.writeValueAsBytes(record));
    }

    // ── New Apple users ────────────────────────────────────────────────────────

    @Test
    @DisplayName("New Apple user without a username is asked to pick one, nothing is created")
    void newUserNeedsUsername() {
        AuthResponse response = signIn(token("new@icloud.com"), null, null);

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo(AppleSignInService.USERNAME_REQUIRED);
        assertThat(response.getToken()).isNull();
        assertThat(s3.objectCount()).isZero();
    }

    @Test
    @DisplayName("New Apple user with a username gets an Apple account, with no phone verification step")
    void newUserCreatesAccount() throws Exception {
        AuthResponse response = signIn(token("new@icloud.com"), "NewUser", null);

        assertThat(response.isSuccess()).isTrue();
        assertThat(response.getToken()).isNotBlank();
        assertThat(response.getError()).isNull(); // Apple already verified them
        assertThat(response.getDisplayUsername()).isEqualTo("NewUser");

        S3UserRecord record = record("newuser");
        assertThat(record.getIsApple()).isTrue();
        assertThat(record.getIsGoogle()).isFalse();
        assertThat(record.getAppleSub()).isEqualTo(SUBJECT);
        assertThat(record.getEmail()).isEqualTo("new@icloud.com");
        assertThat(authService.usernameForEmail("new@icloud.com")).isEqualTo("newuser");
        assertThat(s3.contains("apple-users/" + SUBJECT + ".json")).isTrue();
    }

    @Test
    @DisplayName("Apple-created accounts can't be signed into with a password")
    void appleAccountRejectsPasswordLogin() {
        signIn(token("new@icloud.com"), "newuser", null);

        assertThat(authService.userLogin("newuser", "anything")).isEqualTo("Please sign in with Apple!");
    }

    @Test
    @DisplayName("Username that's already taken is rejected")
    void usernameTaken() {
        authService.createUser("555", "someone@else.com", "taken", "taken", "Password1", false);

        AuthResponse response = signIn(token("new@icloud.com"), "Taken", null);

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo("Username already taken");
        assertThat(s3.contains("apple-users/" + SUBJECT + ".json")).isFalse();
    }

    @Test
    @DisplayName("Usernames with symbols or spaces are rejected")
    void usernameMustBeAlphanumeric() {
        AuthResponse response = signIn(token("new@icloud.com"), "bad name!", null);

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo("Username can only contain letters and numbers.");
    }

    // ── Returning Apple users ──────────────────────────────────────────────────

    @Test
    @DisplayName("Returning Apple user signs straight in, even without an email in the token")
    void returningUserSignsIn() throws Exception {
        signIn(token("new@icloud.com"), "NewUser", null);

        AuthResponse again = signIn(token(null), null, null);
        assertThat(again.isSuccess()).isTrue();
        assertThat(again.getToken()).isNotBlank();
        assertThat(again.getError()).isNull();
        assertThat(again.getDisplayUsername()).isEqualTo("NewUser");
    }

    @Test
    @DisplayName("Stale Apple link to an account that isn't tied to this Apple ID doesn't sign in")
    void staleLinkIgnored() throws Exception {
        // e.g. the linked account was deleted and someone else later took the username
        authService.createUser("555", "other@person.com", "reused", "reused", "Password1", false);
        s3.putRaw("apple-users/" + SUBJECT + ".json", "{\"username\":\"reused\"}".getBytes());

        AuthResponse response = signIn(token("new@icloud.com"), null, null);

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo(AppleSignInService.USERNAME_REQUIRED);
    }

    // ── Linking to an existing account ─────────────────────────────────────────

    @Test
    @DisplayName("Email matching a password account asks for that account's password")
    void existingEmailRequiresPassword() {
        authService.createUser("555", "me@icloud.com", "existing", "Existing", "Password1", false);

        AuthResponse response = signIn(token("Me@iCloud.com"), null, null);

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo(AppleSignInService.LINK_REQUIRED);
        assertThat(response.getDisplayUsername()).isEqualTo("Existing");
        assertThat(response.getToken()).isNull();
    }

    @Test
    @DisplayName("Wrong password does not link the accounts")
    void wrongPasswordDoesNotLink() {
        authService.createUser("555", "me@icloud.com", "existing", "Existing", "Password1", false);

        AuthResponse response = signIn(token("me@icloud.com"), null, "wrong");

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo("Incorrect Password");
        assertThat(s3.contains("apple-users/" + SUBJECT + ".json")).isFalse();
    }

    @Test
    @DisplayName("Correct password links the accounts, and later Apple sign-ins need no password")
    void correctPasswordLinks() throws Exception {
        authService.createUser("555", "me@icloud.com", "existing", "Existing", "Password1", false);
        markVerified("existing");

        AuthResponse linked = signIn(token("me@icloud.com"), null, "Password1");
        assertThat(linked.isSuccess()).isTrue();
        assertThat(linked.getToken()).isNotBlank();
        assertThat(linked.getError()).isNull();
        assertThat(linked.getDisplayUsername()).isEqualTo("Existing");

        AuthResponse again = signIn(token("me@icloud.com"), null, null);
        assertThat(again.isSuccess()).isTrue();
        assertThat(again.getDisplayUsername()).isEqualTo("Existing");
        assertThat(record("existing").getAppleSub()).isEqualTo(SUBJECT);

        // the original password still works too
        assertThat(authService.userLogin("existing", "Password1")).isEqualTo("true");
    }

    @Test
    @DisplayName("Linking Apple to a password account that never verified its phone still asks for verification")
    void linkedUnverifiedPasswordAccountStillVerifies() {
        authService.createUser("555", "me@icloud.com", "existing", "Existing", "Password1", false);

        AuthResponse linked = signIn(token("me@icloud.com"), null, "Password1");

        assertThat(linked.isSuccess()).isTrue();
        assertThat(linked.getError()).isEqualTo("Needs Verification");
    }

    @Test
    @DisplayName("Email matching a Google account points the user to Google sign-in")
    void existingGoogleAccount() {
        authService.createUser("", "me@gmail.com", "googler", "googler", "google-sub", true);

        AuthResponse response = signIn(token("me@gmail.com"), null, "google-sub");

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo("This email is linked to a Google account. Please sign in with Google.");
        assertThat(s3.contains("apple-users/" + SUBJECT + ".json")).isFalse();
    }

    // ── Token verification ─────────────────────────────────────────────────────

    @Test
    @DisplayName("Token whose nonce doesn't match the one the app sent is rejected")
    void nonceMismatch() {
        AuthResponse response = service.signIn(
                new AppleSigninRequest(token("new@icloud.com"), "some-other-nonce", "NewUser", null));

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo("Invalid Apple ID Token");
        assertThat(s3.objectCount()).isZero();
    }

    @Test
    @DisplayName("Token issued for a different app is rejected")
    void wrongAudience() {
        AuthResponse response = signIn(token("new@icloud.com", b -> b.withAudience("com.someone.else")), "NewUser", null);

        assertThat(response.getError()).isEqualTo("Invalid Apple ID Token");
    }

    @Test
    @DisplayName("Token not issued by Apple is rejected")
    void wrongIssuer() {
        AuthResponse response = signIn(token("new@icloud.com", b -> b.withIssuer("https://evil.example")), "NewUser", null);

        assertThat(response.getError()).isEqualTo("Invalid Apple ID Token");
    }

    @Test
    @DisplayName("Token signed by a key Apple doesn't publish is rejected")
    void forgedSignature() {
        String forged = JWT.create()
                .withKeyId(KEY_ID)
                .withIssuer("https://appleid.apple.com")
                .withAudience(AUDIENCE)
                .withSubject(SUBJECT)
                .withExpiresAt(Date.from(Instant.now().plus(10, ChronoUnit.MINUTES)))
                .withClaim("nonce", AppleIdTokenVerifier.sha256Hex(NONCE))
                .withClaim("email", "new@icloud.com")
                .withClaim("email_verified", true)
                .sign(Algorithm.RSA256(null, (RSAPrivateKey) otherKeys.getPrivate()));

        AuthResponse response = signIn(forged, "NewUser", null);

        assertThat(response.getError()).isEqualTo("Invalid Apple ID Token");
        assertThat(s3.objectCount()).isZero();
    }

    @Test
    @DisplayName("Expired token gets a try-again message")
    void expiredToken() {
        AuthResponse response = signIn(token("new@icloud.com",
                b -> b.withExpiresAt(Date.from(Instant.now().minus(10, ChronoUnit.MINUTES)))), "NewUser", null);

        assertThat(response.getError()).isEqualTo("Apple sign-in expired. Please try again.");
    }

    @Test
    @DisplayName("Unverified email is ignored, so it can't claim someone else's account")
    void unverifiedEmailIgnored() {
        authService.createUser("555", "me@icloud.com", "existing", "Existing", "Password1", false);

        AuthResponse response = signIn(token("me@icloud.com", b -> b.withClaim("email_verified", false)), null, "Password1");

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo("Email not available from Apple");
    }

    @Test
    @DisplayName("email_verified sent as the string \"true\" is accepted")
    void emailVerifiedAsString() {
        AuthResponse response = signIn(token("new@icloud.com", b -> b.withClaim("email_verified", "true")), "NewUser", null);

        assertThat(response.isSuccess()).isTrue();
    }

    @Test
    @DisplayName("Subject with path characters is rejected before it can reach an S3 key")
    void unsafeSubjectRejected() {
        AuthResponse response = signIn(token("new@icloud.com", b -> b.withSubject("../users/victim")), "NewUser", null);

        assertThat(response.getError()).isEqualTo("Invalid Apple ID Token");
        assertThat(s3.objectCount()).isZero();
    }
}
