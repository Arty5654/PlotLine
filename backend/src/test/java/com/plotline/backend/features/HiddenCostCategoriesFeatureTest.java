package com.plotline.backend.features;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.fasterxml.jackson.databind.JsonNode;

class HiddenCostCategoriesFeatureTest extends FeatureTestBase {

    @Test
    @DisplayName("Categories removed from Monthly Costs stay hidden; only the owner can change them")
    void hidden() throws Exception {
        User me = newUser();
        assertThat(ok(getAs(me, "/api/costs/hidden/{u}", me.name())).get("hidden").size()).isZero();

        ok(putJson(me, "/api/costs/hidden/" + me.name(), Map.of("hidden", List.of("Travel", "Gifts & Donations", "Travel", " "))));
        JsonNode hidden = ok(getAs(me, "/api/costs/hidden/{u}", me.name())).get("hidden");
        assertThat(hidden.toString()).isEqualTo("[\"Travel\",\"Gifts & Donations\"]");   // no repeats or blanks

        // the monthly costs route next to it still works
        ok(getAs(me, "/api/costs/monthly/{u}", me.name()).param("month", "2026-10"));

        User other = newUser();
        call(putJson(other, "/api/costs/hidden/" + me.name(), Map.of("hidden", List.of())), 403);
    }
}
