package com.plotline.backend.features;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/** Profile page: profile details, picture, phone, trophies, membership. */
class ProfileFeatureTest extends FeatureTestBase {

    @Test
    @DisplayName("Save and read your profile")
    void profile() throws Exception {
        User me = newUser();
        ok(putJson(me, "/profile/save-user", Map.of("username", me.name(), "name", "Sam Lee",
                "birthday", "2003-04-05", "city", "Columbus")));

        JsonNode profile = ok(getAs(me, "/profile/get-user").param("username", me.name()));
        assertThat(profile.get("name").asText()).isEqualTo("Sam Lee");
        assertThat(profile.get("city").asText()).isEqualTo("Columbus");
    }

    @Test
    @DisplayName("Your phone number is readable only by you")
    void phone() throws Exception {
        User me = newUser();
        User other = newUser();
        assertThat(ok(getAs(me, "/profile/get-phone").param("username", me.name())).asText()).contains("5555550123");
        call(getAs(other, "/profile/get-phone").param("username", me.name()), 403);
    }

    @Test
    @DisplayName("Upload a profile picture and get its URL")
    void profilePicture() throws Exception {
        User me = newUser();
        MockMultipartFile image = new MockMultipartFile("file", "me.jpg", "image/jpeg", new byte[]{1, 2, 3});
        ok(as(me, multipart("/profile/upload-profile-pic").file(image).param("username", me.name())));

        JsonNode pic = ok(getAs(me, "/profile/get-profile-pic").param("username", me.name()));
        assertThat(pic.get("profilePicUrl").asText()).contains(me.name());
    }

    @Test
    @DisplayName("Trophies: defaults exist and progress goes up")
    void trophies() throws Exception {
        User me = newUser();
        ok(as(me, post("/profile/create-default-trophies").param("username", me.name())));
        JsonNode trophies = ok(getAs(me, "/profile/get-trophies").param("username", me.name()));
        assertThat(trophies.size()).isGreaterThan(0);
        String trophyId = trophies.get(0).get("id").asText();
        int before = trophies.get(0).get("progress").asInt();

        ok(as(me, post("/profile/increment-trophies").param("username", me.name())
                .param("trophyId", trophyId).param("amount", "1")));

        JsonNode after = ok(getAs(me, "/profile/get-trophies").param("username", me.name()));
        for (JsonNode t : after) {
            if (t.get("id").asText().equals(trophyId)) assertThat(t.get("progress").asInt()).isGreaterThan(before);
        }
    }

    @Test
    @DisplayName("Membership: status loads, and free trials can't be started outside the App Store")
    void membership() throws Exception {
        User me = newUser();
        String plan = ok(getAs(me, "/api/payments/status/{u}", me.name())).get("plan").asText();
        assertThat(plan).isIn("lifetime", "none"); // the first 1,000 accounts are free forever

        // the old server-side trial endpoints could be called again and again for a fresh 30 days
        call(postJson(me, "/api/payments/claim", Map.of("username", me.name())), 404);
        call(postJson(me, "/api/payments/cancel", Map.of("username", me.name())), 404);
        assertThat(ok(getAs(me, "/api/payments/status/{u}", me.name())).get("plan").asText()).isEqualTo(plan);
    }
}
