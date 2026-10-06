package com.plotline.backend.features;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.TextNode;
import com.plaid.client.request.PlaidApi;
import com.plotline.backend.service.AuthService;
import com.plotline.backend.service.OpenAIService;
import com.plotline.backend.service.SmsService;
import com.plotline.backend.testsupport.InMemoryS3Client;
import io.github.cdimascio.dotenv.Dotenv;
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
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

/**
 * Base for feature tests: the whole backend (real controllers, services, login-token and
 * ownership checks) running against in-memory S3. Only services that reach outside the
 * app are faked: OpenAI, Twilio (SMS) and Plaid.
 *
 * All feature test classes share one Spring context, so each test creates its own users
 * with unique names instead of relying on a clean store.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(FeatureTestBase.InMemoryStorage.class)
abstract class FeatureTestBase {

    @TestConfiguration
    static class InMemoryStorage {
        @Bean
        @Primary
        S3Client inMemoryS3() {
            return new InMemoryS3Client();
        }
    }

    @MockBean protected SmsService smsService;
    @MockBean protected OpenAIService openAIService;
    @MockBean protected PlaidApi plaidApi;

    @Autowired protected MockMvc mockMvc;
    @Autowired protected AuthService authService;
    @Autowired protected S3Client s3;

    protected final ObjectMapper objectMapper = new ObjectMapper();

    /** A signed-in user: their username and login token. */
    protected record User(String name, String token) { }

    // the API key filter is active when a key is configured (locally via .env, not in CI)
    private static final String API_KEY = resolveApiKey();

    private static String resolveApiKey() {
        String key = System.getenv("PLOTLINE_API_KEY");
        return key != null && !key.isBlank() ? key : Dotenv.configure().ignoreIfMissing().load().get("PLOTLINE_API_KEY");
    }

    // ── Users ──────────────────────────────────────────────────────────────────

    /** Signs up a new password account (terms accepted, phone verified) with a unique name. */
    protected User newUser() throws Exception {
        String name = "t" + UUID.randomUUID().toString().replace("-", "").substring(0, 12);
        JsonNode response = call(withKey(post("/auth/signup")).contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(Map.of(
                        "username", name, "email", name + "@example.com", "phone", "5555550123",
                        "password", "Password1", "acceptedTerms", true))), 200);
        assertThat(response.get("success").asBoolean()).as("sign up " + name).isTrue();
        authService.updateUserRecord(name, r -> r.setIsVerified(true)); // as if the SMS code was entered
        return new User(name, response.get("token").asText());
    }

    /** Makes two users friends through the real friend-request endpoints. */
    protected void befriend(User a, User b) throws Exception {
        call(json(a, put("/friends/request"),
                Map.of("senderUsername", a.name(), "receiverUsername", b.name(), "status", "PENDING")), 200);
        call(json(b, put("/friends/request"),
                Map.of("senderUsername", a.name(), "receiverUsername", b.name(), "status", "ACCEPTED")), 200);
    }

    // ── Requests ───────────────────────────────────────────────────────────────

    protected MockHttpServletRequestBuilder withKey(MockHttpServletRequestBuilder request) {
        return API_KEY == null || API_KEY.isBlank() ? request : request.header("X-API-Key", API_KEY);
    }

    protected MockHttpServletRequestBuilder as(User user, MockHttpServletRequestBuilder request) {
        return withKey(request).header("Authorization", "Bearer " + user.token());
    }

    protected MockHttpServletRequestBuilder json(User user, MockHttpServletRequestBuilder request, Object body) throws Exception {
        return as(user, request).contentType(MediaType.APPLICATION_JSON).content(objectMapper.writeValueAsString(body));
    }

    protected MockHttpServletRequestBuilder getAs(User user, String path, Object... uriVars) {
        return as(user, get(path, uriVars));
    }

    protected MockHttpServletRequestBuilder deleteAs(User user, String path, Object... uriVars) {
        return as(user, delete(path, uriVars));
    }

    protected MockHttpServletRequestBuilder postJson(User user, String path, Object body) throws Exception {
        return json(user, post(path), body);
    }

    protected MockHttpServletRequestBuilder putJson(User user, String path, Object body) throws Exception {
        return json(user, put(path), body);
    }

    protected MockHttpServletRequestBuilder patchAs(User user, String path, Object... uriVars) {
        return as(user, patch(path, uriVars));
    }

    /** Performs the request, checks the status, and returns the body (JSON, or text wrapped as a TextNode). */
    protected JsonNode call(MockHttpServletRequestBuilder request, int expectedStatus) throws Exception {
        MvcResult result = mockMvc.perform(request).andReturn();
        String body = result.getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
        assertThat(result.getResponse().getStatus())
                .as("%s %s -> %s", result.getRequest().getMethod(), result.getRequest().getRequestURI(), body)
                .isEqualTo(expectedStatus);
        if (body.isBlank()) return TextNode.valueOf("");
        String trimmed = body.trim();
        if (trimmed.startsWith("{") || trimmed.startsWith("[")) return objectMapper.readTree(trimmed);
        return TextNode.valueOf(body);
    }

    protected JsonNode ok(MockHttpServletRequestBuilder request) throws Exception {
        return call(request, 200);
    }

    protected JsonNode bytes(String key) throws Exception {
        return objectMapper.readTree(s3.getObjectAsBytes(b -> b.bucket("plotline-database-bucket").key(key)).asByteArray());
    }
}
