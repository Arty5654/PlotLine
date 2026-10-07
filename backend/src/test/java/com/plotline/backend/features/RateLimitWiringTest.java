package com.plotline.backend.features;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plaid.client.request.PlaidApi;
import com.plotline.backend.service.AuthService;
import com.plotline.backend.service.OpenAIService;
import com.plotline.backend.service.SmsService;
import io.github.cdimascio.dotenv.Dotenv;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/**
 * The real app with rate limits ON: proves the filters are wired in the right order
 * (the AI cap runs after the login filter has identified the user).
 */
@SpringBootTest(properties = {"plotline.ratelimit.enabled=true", "plotline.membership.required=false"})
@AutoConfigureMockMvc
@Import(FeatureTestBase.InMemoryStorage.class)
class RateLimitWiringTest {

    @MockBean private SmsService smsService;
    @MockBean private OpenAIService openAIService;
    @MockBean private PlaidApi plaidApi;

    @Autowired private MockMvc mockMvc;
    @Autowired private AuthService authService;
    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final String API_KEY = resolveApiKey();

    private static String resolveApiKey() {
        String key = System.getenv("PLOTLINE_API_KEY");
        return key != null && !key.isBlank() ? key : Dotenv.configure().ignoreIfMissing().load().get("PLOTLINE_API_KEY");
    }

    private MockHttpServletRequestBuilder withKey(MockHttpServletRequestBuilder request) {
        return API_KEY == null || API_KEY.isBlank() ? request : request.header("X-API-Key", API_KEY);
    }

    @Test
    @DisplayName("Signed-in user: 50 AI requests a day, the 51st gets 429")
    void aiCapInRealApp() throws Exception {
        when(openAIService.ratePortfolio(anyString(), anyString())).thenReturn("{\"score\": 7}");
        String body = objectMapper.writeValueAsString(Map.of("username", "ailimit", "email", "ailimit@example.com",
                "phone", "5555550123", "password", "Password1", "acceptedTerms", true));
        JsonNode signUp = objectMapper.readTree(mockMvc.perform(withKey(post("/auth/signup"))
                .header("Fly-Client-IP", "203.0.113.50").contentType(MediaType.APPLICATION_JSON).content(body))
                .andReturn().getResponse().getContentAsString());
        String token = signUp.get("token").asText();
        authService.updateUserRecord("ailimit", r -> r.setIsVerified(true));

        String rate = objectMapper.writeValueAsString(Map.of("username", "ailimit", "portfolio", "VTI: 100%", "account", "BROKERAGE"));
        int ok = 0;
        int last = 0;
        for (int i = 0; i < 51; i++) {
            last = mockMvc.perform(withKey(post("/api/llm/portfolio/rate")).header("Authorization", "Bearer " + token)
                    .contentType(MediaType.APPLICATION_JSON).content(rate)).andReturn().getResponse().getStatus();
            if (last == 200) ok++;
        }
        assertThat(ok).isEqualTo(50);
        assertThat(last).isEqualTo(429);
    }

    @Test
    @DisplayName("Password sign-in: wrong passwords still reach the server 10 times, then 429")
    void signInLimitInRealApp() throws Exception {
        String body = "{\"username\":\"nobodyhere\",\"password\":\"Wrong1234\"}";
        int last = 0;
        for (int i = 0; i < 11; i++) {
            last = mockMvc.perform(withKey(post("/auth/signin")).header("Fly-Client-IP", "203.0.113.99")
                    .contentType(MediaType.APPLICATION_JSON).content(body)).andReturn().getResponse().getStatus();
            if (i < 10) assertThat(last).as("attempt " + (i + 1)).isEqualTo(200); // normal "Username does not exist" answer
        }
        assertThat(last).isEqualTo(429);
    }
}
