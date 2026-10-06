package com.plotline.backend.security;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plaid.client.request.PlaidApi;
import com.plotline.backend.categorize.UserCategoryStore;
import com.plotline.backend.plaid.PlaidCursorStore;
import com.plotline.backend.plaid.TokenStore;
import com.plotline.backend.service.FriendsFeedService;
import com.plotline.backend.service.LongTermGoalsService;
import com.plotline.backend.service.S3Service;
import com.plotline.backend.service.SmsService;
import com.plotline.backend.service.WeeklyGoalsService;
import com.plotline.backend.testsupport.InMemoryS3Client;
import io.github.cdimascio.dotenv.Dotenv;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import software.amazon.awssdk.services.s3.S3Client;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

/**
 * The whole backend (real controllers, services, auth filter and ownership checks) against an
 * in-memory S3. Only things that would reach AWS/Twilio/Plaid directly are mocked.
 * Walks through: sign up, use your data, get blocked from others', befriend, refresh, delete.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(FullStackAuthFlowTest.InMemoryStorage.class)
class FullStackAuthFlowTest {

    @TestConfiguration
    static class InMemoryStorage {
        @Bean
        @Primary
        S3Client inMemoryS3() {
            return new InMemoryS3Client();
        }
    }

    // these build their own AWS/Twilio/Plaid clients, so keep them out of the test
    @MockBean private TokenStore tokenStore;
    @MockBean private PlaidCursorStore plaidCursorStore;
    @MockBean private UserCategoryStore userCategoryStore;
    @MockBean private S3Service s3Service;
    @MockBean private FriendsFeedService friendsFeedService;
    @MockBean private SmsService smsService;
    @MockBean private WeeklyGoalsService weeklyGoalsService;
    @MockBean private LongTermGoalsService longTermGoalsService;
    @MockBean private PlaidApi plaidApi;

    @Autowired private MockMvc mockMvc;
    @Autowired private com.plotline.backend.service.AuthService authService;
    private final ObjectMapper objectMapper = new ObjectMapper();

    // the API key filter is active if a key is configured locally
    private static final String API_KEY = resolveApiKey();

    private static String resolveApiKey() {
        String key = System.getenv("PLOTLINE_API_KEY");
        return key != null && !key.isBlank() ? key : Dotenv.configure().ignoreIfMissing().load().get("PLOTLINE_API_KEY");
    }

    private MockHttpServletRequestBuilder withKey(MockHttpServletRequestBuilder request) {
        return API_KEY == null || API_KEY.isBlank() ? request : request.header("X-API-Key", API_KEY);
    }

    private MockHttpServletRequestBuilder as(String token, MockHttpServletRequestBuilder request) {
        return withKey(request).header("Authorization", "Bearer " + token);
    }

    private JsonNode call(MockHttpServletRequestBuilder request, int expectedStatus) throws Exception {
        MvcResult result = mockMvc.perform(request).andReturn();
        assertThat(result.getResponse().getStatus())
                .as("%s %s", result.getRequest().getMethod(), result.getRequest().getRequestURI())
                .isEqualTo(expectedStatus);
        String body = result.getResponse().getContentAsString();
        return body.isBlank() || !body.trim().startsWith("{") ? null : objectMapper.readTree(body);
    }

    private String signUp(String username, String email) throws Exception {
        JsonNode response = call(withKey(post("/auth/signup")).contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(Map.of("username", username, "email", email,
                        "phone", "5555550123", "password", "Password1", "acceptedTerms", true))), 200);
        assertThat(response.get("success").asBoolean()).as("sign up %s", username).isTrue();
        return response.get("token").asText();
    }

    // what the real SmsService does when Twilio approves a code (SmsService is mocked here)
    private void markPhoneVerified(String username) {
        authService.updateUserRecord(username, r -> r.setIsVerified(true));
    }

    private MockHttpServletRequestBuilder json(String token, MockHttpServletRequestBuilder request, Object body) throws Exception {
        return as(token, request).contentType(MediaType.APPLICATION_JSON).content(objectMapper.writeValueAsString(body));
    }

    @Test
    @DisplayName("Sign up, stay in your own lane, befriend, refresh, delete")
    void fullFlow() throws Exception {
        when(tokenStore.listAccessTokens(anyString())).thenReturn(Map.of());

        String alice = signUp("alice", "alice@mail.com");
        String bob = signUp("bob", "bob@mail.com");
        markPhoneVerified("alice");
        markPhoneVerified("bob");

        // your own data works; no token or someone else's data doesn't
        call(as(alice, get("/friends/get-friends").param("username", "alice")), 200);
        call(withKey(get("/friends/get-friends").param("username", "alice")), 401);
        call(as(bob, get("/friends/get-friends").param("username", "alice")), 403);
        call(as(alice, get("/profile/get-phone").param("username", "bob")), 403);

        // bob's grocery lists are bob's
        call(json(bob, post("/api/groceryLists/create-grocery-list"),
                Map.of("username", "bob", "name", "Bob's list", "items", java.util.List.of())), 200);
        call(as(alice, get("/api/groceryLists/get-grocery-lists/bob")), 403);
        call(json(alice, post("/api/groceryLists/create-grocery-list"),
                Map.of("username", "bob", "name", "Planted", "items", java.util.List.of())), 403);

        // bob fills in his profile; alice can't overwrite it
        call(json(bob, put("/profile/save-user"),
                Map.of("username", "bob", "name", "Bob Builder", "birthday", "2000-01-01", "city", "Boston")), 200);
        call(json(alice, put("/profile/save-user"),
                Map.of("username", "bob", "name", "Hacked", "birthday", "2000-01-01", "city", "Nowhere")), 403);

        // strangers only see a username
        JsonNode stranger = call(as(alice, get("/profile/get-user").param("username", "bob")), 200);
        assertThat(stranger.path("name").isMissingNode() || stranger.path("name").isNull()).isTrue();
        assertThat(stranger.path("city").isMissingNode() || stranger.path("city").isNull()).isTrue();

        // friendship: alice asks, can't accept for bob, bob accepts
        call(json(alice, put("/friends/request"),
                Map.of("senderUsername", "alice", "receiverUsername", "bob", "status", "PENDING")), 200);
        call(json(alice, put("/friends/request"),
                Map.of("senderUsername", "alice", "receiverUsername", "bob", "status", "ACCEPTED")), 403);
        call(json(bob, put("/friends/request"),
                Map.of("senderUsername", "alice", "receiverUsername", "bob", "status", "ACCEPTED")), 200);
        JsonNode friends = call(as(alice, get("/friends/get-friends").param("username", "alice")), 200);
        assertThat(friends.get("friends").toString()).contains("bob");
        // friends see the full profile
        JsonNode friendView = call(as(alice, get("/profile/get-user").param("username", "bob")), 200);
        assertThat(friendView.get("name").asText()).isEqualTo("Bob Builder");
        assertThat(friendView.get("city").asText()).isEqualTo("Boston");

        // refresh gives a working token
        JsonNode refreshed = call(as(alice, post("/auth/refresh")), 200);
        String aliceFresh = refreshed.get("token").asText();
        call(as(aliceFresh, get("/friends/get-friends").param("username", "alice")), 200);

        // delete alice: her tokens stop working, bob no longer lists her
        call(json(alice, post("/auth/delete-account"), Map.of()), 200);
        call(as(alice, get("/friends/get-friends").param("username", "alice")), 401);
        call(as(aliceFresh, post("/auth/refresh")), 401);
        JsonNode bobsFriends = call(as(bob, get("/friends/get-friends").param("username", "bob")), 200);
        assertThat(bobsFriends.get("friends").toString()).doesNotContain("alice");

        // someone new takes the name "alice": the old tokens still can't get in
        Thread.sleep(1100); // tokens record time to the second
        String newAlice = signUp("alice", "new-alice@mail.com");
        markPhoneVerified("alice");
        call(as(newAlice, get("/friends/get-friends").param("username", "alice")), 200);
        call(as(aliceFresh, get("/friends/get-friends").param("username", "alice")), 401);
    }

    @Test
    @DisplayName("Terms: public pages, required at sign-up, one-time acceptance for everyone else")
    void termsFlow() throws Exception {
        // the pages are public: no login token or API key (App Store Connect links to /privacy)
        MvcResult terms = mockMvc.perform(get("/terms")).andReturn();
        assertThat(terms.getResponse().getStatus()).isEqualTo(200);
        assertThat(terms.getResponse().getContentAsString()).contains("Terms of Service", "18");
        MvcResult privacy = mockMvc.perform(get("/privacy")).andReturn();
        assertThat(privacy.getResponse().getStatus()).isEqualTo(200);
        assertThat(privacy.getResponse().getContentAsString()).contains("Privacy Policy", "Plaid");

        // sign-up without agreeing is refused
        JsonNode refused = call(withKey(post("/auth/signup")).contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(Map.of("username", "carol", "email", "carol@mail.com",
                        "phone", "5555550123", "password", "Password1"))), 200);
        assertThat(refused.get("success").asBoolean()).isFalse();
        assertThat(refused.get("error").asText()).contains("Terms of Service");
        assertThat(authService.userExists("carol")).isFalse();

        // agreeing at sign-up is recorded, so sign-in doesn't ask again
        String carol = signUp("carol", "carol@mail.com");
        assertThat(authService.getUserRecord("carol").getTermsVersion())
                .isEqualTo(com.plotline.backend.controller.LegalController.TERMS_VERSION);
        assertThat(authService.getUserRecord("carol").getTermsAcceptedAt()).isNotNull();
        JsonNode signIn = call(withKey(post("/auth/signin")).contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\":\"carol\",\"password\":\"Password1\"}"), 200);
        assertThat(signIn.get("needsTerms").asBoolean()).isFalse();

        // an existing account that never agreed (or agreed to an older version) is asked once
        authService.updateUserRecord("carol", r -> r.setTermsVersion("2025-01-01"));
        JsonNode refreshed = call(as(carol, post("/auth/refresh")), 200);
        assertThat(refreshed.get("needsTerms").asBoolean()).isTrue();

        JsonNode accepted = call(as(carol, post("/auth/accept-terms")), 200);
        assertThat(accepted.get("success").asBoolean()).isTrue();
        assertThat(call(as(carol, post("/auth/refresh")), 200).get("needsTerms").asBoolean()).isFalse();

        // accepting needs a signed-in user
        call(withKey(post("/auth/accept-terms")), 401);
    }

    @Test
    @DisplayName("Unfinished setup (phone verification, terms) blocks the app on the server, not just in the UI")
    void setupStepsAreEnforced() throws Exception {
        when(smsService.verifyCode(anyString(), anyString(), anyString())).thenReturn(true);
        String dave = signUp("dave", "dave@mail.com");

        // closing and reopening the app doesn't help: the server itself refuses until the phone is verified
        JsonNode blocked = call(as(dave, get("/friends/get-friends").param("username", "dave")), 403);
        assertThat(blocked.get("error").asText()).isEqualTo("Needs Verification");
        JsonNode refreshed = call(as(dave, post("/auth/refresh")), 200);
        assertThat(refreshed.get("error").asText()).isEqualTo("Needs Verification");

        // the verification step itself is reachable
        call(json(dave, post("/sms/verify-code"),
                Map.of("phoneNumber", "5555550123", "code", "123456", "username", "dave")), 200);
        markPhoneVerified("dave");
        call(as(dave, get("/friends/get-friends").param("username", "dave")), 200);
        assertThat(call(as(dave, post("/auth/refresh")), 200).path("error").isNull()).isTrue();

        // same for the terms: an outdated acceptance blocks everything except accepting them
        authService.updateUserRecord("dave", r -> r.setTermsVersion("2025-01-01"));
        JsonNode needsTerms = call(as(dave, get("/friends/get-friends").param("username", "dave")), 403);
        assertThat(needsTerms.get("error").asText()).isEqualTo("Needs Terms");
        call(as(dave, post("/auth/accept-terms")), 200);
        call(as(dave, get("/friends/get-friends").param("username", "dave")), 200);
    }
}
