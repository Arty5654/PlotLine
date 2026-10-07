package com.plotline.backend.ratelimit;

import com.plotline.backend.security.CurrentUser;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/** The filters in front of the real endpoints, with a stand-in controller that echoes the body back. */
class RateLimitFiltersTest {

    @RestController
    static class EchoController {
        @PostMapping({"/auth/signin", "/auth/signup", "/auth/google-signin", "/auth/apple-signin",
                "/sms/send-verification", "/sms/verify-code", "/auth/change-password-code", "/auth/change-password",
                "/api/llm/portfolio", "/api/costs/upload-receipt", "/api/budget"})
        String echo(@RequestBody(required = false) String body) {
            return body == null ? "ok" : body;
        }

        @org.springframework.web.bind.annotation.GetMapping("/api/llm/portfolio")
        String read() { return "ok"; }
    }

    private FakeClock clock;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        clock = new FakeClock();
        RateLimiter limiter = new RateLimiter(clock);
        mockMvc = MockMvcBuilders.standaloneSetup(new EchoController())
                .addFilters(new AuthRateLimitFilter(limiter, true), new AiRateLimitFilter(limiter, true))
                .build();
    }

    private MvcResult postJson(String path, String json, String ip) throws Exception {
        return mockMvc.perform(post(path).contentType(MediaType.APPLICATION_JSON).content(json)
                .header("Fly-Client-IP", ip)).andReturn();
    }

    private int okCount(String path, String json, String ip, int attempts) throws Exception {
        int ok = 0;
        for (int i = 0; i < attempts; i++) if (postJson(path, json, ip).getResponse().getStatus() == 200) ok++;
        return ok;
    }

    @Test
    @DisplayName("Sign-in: the 11th try in a minute from one IP gets 429 with a try-again message")
    void signInPerIp() throws Exception {
        for (int i = 0; i < 10; i++) {
            MvcResult ok = postJson("/auth/signin", "{\"username\":\"user" + i + "\",\"password\":\"x\"}", "1.1.1.1");
            assertThat(ok.getResponse().getStatus()).isEqualTo(200);
            assertThat(ok.getResponse().getContentAsString()).contains("user" + i); // body still reaches the controller
        }

        MvcResult blocked = postJson("/auth/signin", "{\"username\":\"user99\",\"password\":\"x\"}", "1.1.1.1");
        assertThat(blocked.getResponse().getStatus()).isEqualTo(429);
        assertThat(blocked.getResponse().getHeader("Retry-After")).isNotBlank();
        assertThat(blocked.getResponse().getContentAsString()).contains("Too many attempts. Try again in 1 minute.");

        // another IP is unaffected
        assertThat(postJson("/auth/signin", "{\"username\":\"user99\"}", "2.2.2.2").getResponse().getStatus()).isEqualTo(200);
    }

    @Test
    @DisplayName("Sign-in: guessing one account's password from many IPs is still limited")
    void signInPerUsername() throws Exception {
        int ok = 0;
        for (int i = 0; i < 15; i++) {
            if (postJson("/auth/signin", "{\"username\":\"Victim\",\"password\":\"guess" + i + "\"}", "10.0.0." + i)
                    .getResponse().getStatus() == 200) ok++;
        }
        assertThat(ok).isEqualTo(10);
    }

    @Test
    @DisplayName("Sign-up: 5 per hour per IP")
    void signUp() throws Exception {
        assertThat(okCount("/auth/signup", "{\"username\":\"new\"}", "3.3.3.3", 8)).isEqualTo(5);
        clock.advance(Duration.ofHours(1));
        assertThat(okCount("/auth/signup", "{\"username\":\"new\"}", "3.3.3.3", 1)).isEqualTo(1);
    }

    @Test
    @DisplayName("Apple/Google sign-in: 20 per minute per IP")
    void socialSignIn() throws Exception {
        assertThat(okCount("/auth/apple-signin", "{}", "4.4.4.4", 15) + okCount("/auth/google-signin", "{}", "4.4.4.4", 15))
                .isEqualTo(20);
    }

    @Test
    @DisplayName("Texts: 3 per 10 minutes to one phone, however the number is formatted")
    void textsPerPhone() throws Exception {
        assertThat(postJson("/sms/send-verification", "{\"toNumber\":\"5555550123\"}", "5.5.5.1").getResponse().getStatus()).isEqualTo(200);
        assertThat(postJson("/sms/send-verification", "{\"toNumber\":\"(555) 555-0123\"}", "5.5.5.2").getResponse().getStatus()).isEqualTo(200);
        assertThat(postJson("/sms/send-verification", "{\"toNumber\":\"555-555-0123\"}", "5.5.5.3").getResponse().getStatus()).isEqualTo(200);
        assertThat(postJson("/sms/send-verification", "{\"toNumber\":\"5555550123\"}", "5.5.5.4").getResponse().getStatus()).isEqualTo(429);

        // a different phone is fine, and the first one can get a code again after 10 minutes
        assertThat(postJson("/sms/send-verification", "{\"toNumber\":\"5555550999\"}", "5.5.5.5").getResponse().getStatus()).isEqualTo(200);
        clock.advance(Duration.ofMinutes(10));
        assertThat(postJson("/sms/send-verification", "{\"toNumber\":\"5555550123\"}", "5.5.5.6").getResponse().getStatus()).isEqualTo(200);
    }

    @Test
    @DisplayName("Texts: 10 per hour from one IP across different phones")
    void textsPerIp() throws Exception {
        int ok = 0;
        for (int i = 0; i < 12; i++) {
            if (postJson("/sms/send-verification", "{\"toNumber\":\"55555501" + (10 + i) + "\"}", "6.6.6.6")
                    .getResponse().getStatus() == 200) ok++;
        }
        assertThat(ok).isEqualTo(10);
    }

    @Test
    @DisplayName("Checking a texted code: 5 per 10 minutes per username (verify and reset share the count)")
    void codeChecks() throws Exception {
        int ok = okCount("/sms/verify-code", "{\"username\":\"alex\",\"code\":\"000000\"}", "7.7.7.7", 3)
                + okCount("/auth/change-password-code", "{\"username\":\"Alex\",\"code\":\"111111\"}", "7.7.7.8", 4);
        assertThat(ok).isEqualTo(5);
    }

    @Test
    @DisplayName("Change password: 5 per 15 minutes per username")
    void changePassword() throws Exception {
        assertThat(okCount("/auth/change-password", "{\"username\":\"alex\",\"oldPassword\":\"x\"}", "8.8.8.8", 7)).isEqualTo(5);
    }

    @Test
    @DisplayName("AI features: 50 per user per day; other users and non-AI requests aren't affected")
    void aiCap() throws Exception {
        int ok = 0;
        for (int i = 0; i < 55; i++) {
            String path = i % 2 == 0 ? "/api/llm/portfolio" : "/api/costs/upload-receipt";
            if (mockMvc.perform(post(path).requestAttr(CurrentUser.ATTRIBUTE, "alex")).andReturn().getResponse().getStatus() == 200) ok++;
        }
        assertThat(ok).isEqualTo(50);

        MvcResult blocked = mockMvc.perform(post("/api/llm/portfolio").requestAttr(CurrentUser.ATTRIBUTE, "alex")).andReturn();
        assertThat(blocked.getResponse().getStatus()).isEqualTo(429);
        assertThat(blocked.getResponse().getContentAsString()).contains("today's limit for AI features");

        assertThat(mockMvc.perform(post("/api/llm/portfolio").requestAttr(CurrentUser.ATTRIBUTE, "sam")).andReturn()
                .getResponse().getStatus()).isEqualTo(200);
        assertThat(mockMvc.perform(post("/api/budget").contentType(MediaType.APPLICATION_JSON).content("{}")
                .requestAttr(CurrentUser.ATTRIBUTE, "alex")).andReturn().getResponse().getStatus()).isEqualTo(200);
        assertThat(mockMvc.perform(get("/api/llm/portfolio").requestAttr(CurrentUser.ATTRIBUTE, "alex")).andReturn()
                .getResponse().getStatus()).isEqualTo(200);
    }

    @Test
    @DisplayName("Turned off (tests, local dev) means no limits")
    void disabled() throws Exception {
        RateLimiter limiter = new RateLimiter(new FakeClock());
        MockMvc unlimited = MockMvcBuilders.standaloneSetup(new EchoController())
                .addFilters(new AuthRateLimitFilter(limiter, false), new AiRateLimitFilter(limiter, false)).build();
        int ok = 0;
        for (int i = 0; i < 20; i++) {
            if (unlimited.perform(post("/auth/signup").contentType(MediaType.APPLICATION_JSON).content("{}"))
                    .andReturn().getResponse().getStatus() == 200) ok++;
        }
        assertThat(ok).isEqualTo(20);
    }
}
