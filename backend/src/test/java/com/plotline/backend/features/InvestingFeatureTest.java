package com.plotline.backend.features;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/** Investing page: AI portfolio, edits and revert, rating, watchlist. */
class InvestingFeatureTest extends FeatureTestBase {

    private static final String PORTFOLIO = "VTI: 60%\nVXUS: 30%\nBND: 10%";

    @Test
    @DisplayName("Save an original portfolio, edit it, revert back to the original")
    void portfolioEditRevert() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/llm/portfolio/save-original", Map.of("username", me.name(),
                "portfolio", PORTFOLIO, "riskTolerance", "Medium", "account", "BROKERAGE")));
        assertThat(ok(getAs(me, "/api/llm/portfolio/{u}", me.name()).param("account", "BROKERAGE")).toString()).contains("VTI");

        ok(postJson(me, "/api/llm/portfolio/save", Map.of("username", me.name(),
                "portfolio", "VTI: 100%", "riskTolerance", "Medium", "account", "BROKERAGE")));
        assertThat(ok(getAs(me, "/api/llm/portfolio/{u}", me.name()).param("account", "BROKERAGE")).get("portfolio").asText())
                .isEqualTo("VTI: 100%");

        ok(as(me, post("/api/llm/portfolio/revert/{u}", me.name())).param("account", "BROKERAGE"));
        assertThat(ok(getAs(me, "/api/llm/portfolio/{u}", me.name()).param("account", "BROKERAGE")).get("portfolio").asText())
                .contains("VXUS");
    }

    @Test
    @DisplayName("AI portfolio generation from the investing quiz")
    void generatePortfolio() throws Exception {
        when(openAIService.generateResponsePortfolio(anyString())).thenReturn(PORTFOLIO);
        User me = newUser();
        JsonNode result = ok(postJson(me, "/api/llm/portfolio", Map.of("username", me.name(), "account", "BROKERAGE",
                "goals", "Retirement", "riskTolerance", "Medium", "experience", "Beginner", "age", "22",
                "timeHorizon", "30 years", "withdrawalFlexibility", "Low", "taxPriorty", "Medium")));
        assertThat(result.toString()).contains("VTI");
    }

    @Test
    @DisplayName("Portfolio rating comes back from the AI")
    void ratePortfolio() throws Exception {
        when(openAIService.ratePortfolio(anyString(), anyString())).thenReturn("{\"score\": 8, \"feedback\": \"Well diversified\"}");
        User me = newUser();
        JsonNode result = ok(postJson(me, "/api/llm/portfolio/rate",
                Map.of("username", me.name(), "portfolio", PORTFOLIO, "account", "BROKERAGE")));
        assertThat(result.toString()).contains("Well diversified");
    }

    @Test
    @DisplayName("Watchlist: add, list, remove")
    void watchlist() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/watchlist/add", Map.of("username", me.name(), "symbol", "AAPL")));
        ok(postJson(me, "/api/watchlist/add", Map.of("username", me.name(), "symbol", "MSFT")));
        assertThat(ok(getAs(me, "/api/watchlist/{u}", me.name())).toString()).contains("AAPL", "MSFT");

        ok(postJson(me, "/api/watchlist/remove", Map.of("username", me.name(), "symbol", "AAPL")));
        assertThat(ok(getAs(me, "/api/watchlist/{u}", me.name())).toString()).doesNotContain("AAPL").contains("MSFT");
    }

    @Test
    @DisplayName("Another user's portfolio is off limits")
    void ownDataOnly() throws Exception {
        User me = newUser();
        User other = newUser();
        call(getAs(me, "/api/llm/portfolio/{u}", other.name()).param("account", "BROKERAGE"), 403);
    }
}
