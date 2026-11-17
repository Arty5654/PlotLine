package com.plotline.backend.features;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Map;
import java.util.Optional;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.fasterxml.jackson.databind.JsonNode;

/** Gas and electricity come from EIA's real prices; the AI only estimates when EIA can't answer. */
class CommutePricesEiaFeatureTest extends FeatureTestBase {

    private Map<String, Object> body(String state, boolean electric) {
        return Map.of("mode", "drive", "homeState", state, "homeCity", "Ashburn", "workPlace", "Reston, VA",
                "electric", electric, "routeHasTolls", false);
    }

    @Test
    @DisplayName("This week's EIA gas price, remembered for a day; no AI question")
    void gasFromEia() throws Exception {
        when(eia.configured()).thenReturn(true);
        when(eia.gasPerGallon("Virginia")).thenReturn(Optional.of(3.071));
        User me = newUser();
        JsonNode gas = ok(postJson(me, "/api/tools/commute-prices", body("Virginia", false))).get("gas");
        assertThat(gas.get("pricePerGallon").asDouble()).isEqualTo(3.071);
        assertThat(gas.get("fromEIA").asDouble()).isEqualTo(1.0);
        ok(postJson(me, "/api/tools/commute-prices", body("Virginia", false)));
        verify(eia, times(1)).gasPerGallon("Virginia");
        verify(openAIService, never()).estimateJson(anyString(), contains("gallon"));
    }

    @Test
    @DisplayName("Electricity for an electric car comes from EIA too")
    void electricityFromEia() throws Exception {
        when(eia.configured()).thenReturn(true);
        when(eia.electricityPerKwh("Colorado")).thenReturn(Optional.of(0.147));
        JsonNode power = ok(postJson(newUser(), "/api/tools/commute-prices", body("Colorado", true))).get("electricity");
        assertThat(power.get("pricePerKwh").asDouble()).isEqualTo(0.147);
    }

    @org.springframework.beans.factory.annotation.Autowired org.springframework.jdbc.core.JdbcTemplate jdbc;

    private void ageSavedPrice(String place, int days) {
        jdbc.update("update price_estimates set updated_at = now() - (? || ' days')::interval where kind = 'gas' and place = ?",
                String.valueOf(days), place);
    }

    @Test
    @DisplayName("Two requests at once ask EIA once and both get its price")
    void oneLookupAtATime() throws Exception {
        when(eia.configured()).thenReturn(true);
        when(eia.gasPerGallon("Maryland")).thenAnswer(i -> { Thread.sleep(300); return Optional.of(4.363); });
        User me = newUser();
        var pool = java.util.concurrent.Executors.newFixedThreadPool(2);
        java.util.concurrent.Callable<Double> ask = () ->
                ok(postJson(me, "/api/tools/commute-prices", body("Maryland", false))).get("gas").get("pricePerGallon").asDouble();
        var a = pool.submit(ask);
        var b = pool.submit(ask);
        assertThat(a.get()).isEqualTo(4.363);
        assertThat(b.get()).isEqualTo(4.363);
        pool.shutdown();
        verify(eia, times(1)).gasPerGallon("Maryland");
        verify(openAIService, never()).estimateJson(anyString(), contains("gallon"));
    }

    @Test
    @DisplayName("If EIA times out, its last price is used (not an AI guess), and a guess never replaces an EIA price")
    void eiaStaysWhenItTimesOut() throws Exception {
        when(eia.configured()).thenReturn(true);
        when(eia.gasPerGallon("Delaware")).thenReturn(Optional.of(3.98), Optional.empty(), Optional.empty());
        when(openAIService.estimateJson(anyString(), contains("gallon"))).thenReturn("{\"pricePerGallon\": 3.45}");
        User me = newUser();
        ok(postJson(me, "/api/tools/commute-prices", body("Delaware", false)));      // EIA: 3.98
        ageSavedPrice("delaware", 2);                                                 // due for a fresh look
        JsonNode gas = ok(postJson(me, "/api/tools/commute-prices", body("Delaware", false))).get("gas");
        assertThat(gas.get("pricePerGallon").asDouble()).isEqualTo(3.98);            // EIA timed out: its last price
        assertThat(gas.get("fromEIA").asDouble()).isEqualTo(1.0);
        verify(openAIService, never()).estimateJson(anyString(), contains("gallon"));

        ageSavedPrice("delaware", 20);                                                // too old to use
        gas = ok(postJson(me, "/api/tools/commute-prices", body("Delaware", false))).get("gas");
        assertThat(gas.get("pricePerGallon").asDouble()).isEqualTo(3.45);            // now a guess...
        String saved = jdbc.queryForObject("select data from price_estimates where kind = 'gas' and place = 'delaware'", String.class);
        assertThat(saved).contains("fromEIA");                                       // ...that didn't replace EIA's
    }

    @Test
    @DisplayName("When EIA can't answer, the AI estimates (and it's marked as not from EIA)")
    void fallback() throws Exception {
        when(eia.configured()).thenReturn(true);
        when(eia.gasPerGallon("Oregon")).thenReturn(Optional.empty());
        when(openAIService.estimateJson(anyString(), contains("gallon"))).thenReturn("{\"pricePerGallon\": 4.05}");
        JsonNode gas = ok(postJson(newUser(), "/api/tools/commute-prices", body("Oregon", false))).get("gas");
        assertThat(gas.get("pricePerGallon").asDouble()).isEqualTo(4.05);
        assertThat(gas.has("fromEIA")).isFalse();
    }
}
