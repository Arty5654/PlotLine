package com.plotline.backend.service;

import com.plotline.backend.accounts.AccountDirectory;
import com.plotline.backend.testsupport.TestDatabase;
import org.springframework.jdbc.core.JdbcTemplate;
import com.plotline.backend.dto.AuthResponse;
import com.plotline.backend.dto.GoogleSigninRequest;
import com.plotline.backend.dto.S3UserRecord;
import com.plotline.backend.service.GoogleTokenVerifier.GoogleIdentity;
import com.plotline.backend.testsupport.InMemoryS3Client;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.bcrypt.BCrypt;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/** Google sign-in: returning users go straight in, new users pick a username. Google itself is faked. */
class GoogleSignInServiceTest {

    private static final String SUB = "109876543210987654321";

    private InMemoryS3Client s3;
    private AuthService authService;
    private GoogleTokenVerifier verifier;
    private GoogleSignInService service;

    @BeforeEach
    void setUp() throws Exception {
        s3 = new InMemoryS3Client();
        JdbcTemplate jdbc = new JdbcTemplate(TestDatabase.newDatabase());
        authService = new AuthService(s3, null, "test-jwt-secret", new AccountDirectory(jdbc));
        verifier = mock(GoogleTokenVerifier.class);
        when(verifier.verify("token")).thenReturn(new GoogleIdentity(SUB, "John.Smith@gmail.com"));
        service = new GoogleSignInService(authService, verifier);
    }

    private AuthResponse signIn(String chosenUsername) {
        return service.signIn(new GoogleSigninRequest("token", chosenUsername, "John.Smith@gmail.com"));
    }

    @Test
    @DisplayName("New Google user is asked to pick a username, with a cleaned-up suggestion from their email")
    void newUserGetsSuggestion() {
        AuthResponse response = signIn(null);

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo(GoogleSignInService.USERNAME_REQUIRED);
        assertThat(response.getDisplayUsername()).isEqualTo("johnsmith"); // emails are lowercased first
        assertThat(authService.userExists("johnsmith")).isFalse();
    }

    @Test
    @DisplayName("Picking a valid username creates the Google account")
    void pickUsername() throws Exception {
        AuthResponse response = signIn("Johnny");

        assertThat(response.isSuccess()).isTrue();
        assertThat(response.getToken()).isNotBlank();
        assertThat(response.getDisplayUsername()).isEqualTo("Johnny");
        S3UserRecord record = new ObjectMapper().readValue(
                s3.getObjectAsBytes(b -> b.bucket("plotline-database-bucket").key("users/johnny/account.json")).asByteArray(),
                S3UserRecord.class);
        assertThat(record.getIsGoogle()).isTrue();
        assertThat(record.getGoogleSub()).isEqualTo(SUB);
        assertThat(record.getEmail()).isEqualTo("john.smith@gmail.com");
    }

    @Test
    @DisplayName("Invalid or taken usernames are refused")
    void badUsernames() {
        authService.createUser("555", "other@mail.com", "taken", "taken", "Password1", false);

        assertThat(signIn("john.smith").getError()).isEqualTo(AuthService.USERNAME_RULES);
        assertThat(signIn("jo").getError()).isEqualTo(AuthService.USERNAME_RULES);
        assertThat(signIn("bob/grocery").getError()).isEqualTo(AuthService.USERNAME_RULES);
        assertThat(signIn("Taken").getError()).isEqualTo("Username already taken");
    }

    @Test
    @DisplayName("Returning Google user goes straight in, whatever username the app sends")
    void returningUser() {
        signIn("Johnny");

        AuthResponse again = signIn(null);

        assertThat(again.isSuccess()).isTrue();
        assertThat(again.getDisplayUsername()).isEqualTo("Johnny");
        assertThat(again.getError()).isNull(); // no phone step for Google
    }

    @Test
    @DisplayName("A different Google account using the same email is refused")
    void differentGoogleAccount() throws Exception {
        signIn("Johnny");
        when(verifier.verify("token")).thenReturn(new GoogleIdentity("999", "john.smith@gmail.com"));

        AuthResponse response = signIn(null);

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo("Google account does not match");
    }

    @Test
    @DisplayName("Older Google accounts (username = email prefix) still sign in")
    void legacyAccount() throws Exception {
        S3UserRecord legacy = new S3UserRecord("john.smith", "john.smith", "", "john.smith@gmail.com",
                BCrypt.hashpw(SUB, BCrypt.gensalt()), true, true);
        s3.putRaw("users/john.smith/account.json", new ObjectMapper().writeValueAsBytes(legacy));

        AuthResponse response = signIn(null);

        assertThat(response.isSuccess()).isTrue();
        assertThat(response.getDisplayUsername()).isEqualTo("john.smith");
    }

    @Test
    @DisplayName("Someone else's older account with the same email prefix isn't signed into; they pick a name instead")
    void legacyPrefixDifferentPerson() throws Exception {
        S3UserRecord legacy = new S3UserRecord("john.smith", "john.smith", "", "john.smith@school.edu",
                BCrypt.hashpw("another-google-id", BCrypt.gensalt()), true, true);
        s3.putRaw("users/john.smith/account.json", new ObjectMapper().writeValueAsBytes(legacy));

        AuthResponse response = signIn(null);

        assertThat(response.getError()).isEqualTo(GoogleSignInService.USERNAME_REQUIRED);
    }

    @Test
    @DisplayName("Email that belongs to a password or Apple account points the user to the right sign-in")
    void emailBelongsToOtherAccount() throws Exception {
        authService.createUser("555", "john.smith@gmail.com", "jsmith", "jsmith", "Password1", false);
        assertThat(signIn(null).getError()).contains("username and password");

        GoogleIdentity appleEmail = new GoogleIdentity(SUB, "me@icloud.com");
        when(verifier.verify("apple-token")).thenReturn(appleEmail);
        authService.createAppleUser("me@icloud.com", "appler", "appler", "001.apple");
        AuthResponse response = service.signIn(new GoogleSigninRequest("apple-token", null, "me@icloud.com"));
        assertThat(response.getError()).contains("Sign in with Apple");
    }

    @Test
    @DisplayName("Invalid Google token is refused")
    void invalidToken() throws Exception {
        when(verifier.verify("forged")).thenReturn(null);

        AuthResponse response = service.signIn(new GoogleSigninRequest("forged", "Johnny", "x@gmail.com"));

        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getError()).isEqualTo("Invalid Google ID Token");
        assertThat(authService.userExists("johnny")).isFalse();
    }
}
