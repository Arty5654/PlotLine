package com.plotline.backend.features;

import com.plotline.backend.external.ExternalDataClient;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.mock.mockito.MockBean;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/** Market news and food search through the real app: signed-in users only. */
class ExternalDataFeatureTest extends FeatureTestBase {

    @MockBean private ExternalDataClient externalDataClient;

    @Test
    @DisplayName("Food search works for signed-in users and is refused without a login")
    void foodSearchNeedsLogin() throws Exception {
        when(externalDataClient.get(anyString())).thenReturn("{\"foods\":[]}");
        User me = newUser();

        assertThat(ok(getAs(me, "/api/nutrition/food-search").param("q", "oats")).toString()).isEqualTo("{\"foods\":[]}");
        call(withKey(get("/api/nutrition/food-search")).param("q", "oats"), 401);
        call(withKey(get("/api/news")), 401);
    }
}
