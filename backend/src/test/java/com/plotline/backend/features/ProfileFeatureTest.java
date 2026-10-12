package com.plotline.backend.features;

import java.util.List;
import com.plotline.backend.testsupport.InMemoryS3Client;
import java.time.temporal.ChronoUnit;
import java.time.Instant;
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
    @DisplayName("A new account that hasn't saved a profile yet gets an empty one, not an error")
    void profileBeforeFirstSave() throws Exception {
        User me = newUser();
        User other = newUser();

        JsonNode profile = ok(getAs(me, "/profile/get-user").param("username", me.name()));
        assertThat(profile.get("username").asText()).isEqualTo(me.name());
        assertThat(profile.get("name").isNull()).isTrue();
        assertThat(profile.get("birthday").isNull()).isTrue();

        assertThat(ok(getAs(other, "/profile/get-user").param("username", me.name())).get("username").asText())
                .isEqualTo(me.name());
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
    @DisplayName("Profile picture: a new picture gets a new address, so the app doesn't show the old one from its cache")
    void profilePicture() throws Exception {
        User me = newUser();
        String before = ok(getAs(me, "/profile/get-profile-pic").param("username", me.name())).get("profilePicUrl").asText();
        assertThat(before).contains(me.name()).doesNotContain("?v="); // none yet

        MockMultipartFile image = new MockMultipartFile("file", "me.jpg", "image/jpeg", new byte[]{1, 2, 3});
        String first = call(as(me, multipart("/profile/upload-profile-pic").file(image).param("username", me.name())), 200).asText();
        assertThat(first).startsWith(before + "?v=");
        String fetched = ok(getAs(me, "/profile/get-profile-pic").param("username", me.name())).get("profilePicUrl").asText();
        assertThat(fetched).isEqualTo(first);

        // saved an hour ago, then changed: the address changes
        String key = "users/" + me.name().toLowerCase() + "/profile_pictures/" + me.name().toLowerCase() + ".jpg";
        ((InMemoryS3Client) s3).setLastModified(key, Instant.now().minus(1, ChronoUnit.HOURS));
        String old = ok(getAs(me, "/profile/get-profile-pic").param("username", me.name())).get("profilePicUrl").asText();
        call(as(me, multipart("/profile/upload-profile-pic").file(image).param("username", me.name())), 200);
        String changed = ok(getAs(me, "/profile/get-profile-pic").param("username", me.name())).get("profilePicUrl").asText();
        assertThat(changed).startsWith(before + "?v=").isNotEqualTo(old);

        // the same picture whatever the capitalization of the username
        String upper = ok(getAs(me, "/profile/get-profile-pic").param("username", me.name().toUpperCase())).get("profilePicUrl").asText();
        assertThat(upper).isEqualTo(changed);
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
    @DisplayName("Trophies: old sleep trophies are removed, and a trophy in every category earns All-Around Achiever")
    void allAroundWithoutSleep() throws Exception {
        User me = newUser();
        ok(as(me, post("/profile/create-default-trophies").param("username", me.name())));
        // an account from when sleep tracking existed
        String key = "users/" + me.name().toLowerCase() + "/trophies.json";
        String stored = new String(s3.getObjectAsBytes(b -> b.bucket("plotline-database-bucket").key(key)).asByteArray());
        String withSleep = stored.substring(0, stored.length() - 1)
                + ",{\"id\":\"sleep-tracker\",\"name\":\"Someone's Sleepy\",\"description\":\"Logged sleep data!\","
                + "\"level\":0,\"progress\":0,\"thresholds\":[3,10,30,100],\"earnedDate\":null}]";
        s3.putObject(b -> b.bucket("plotline-database-bucket").key(key),
                software.amazon.awssdk.core.sync.RequestBody.fromString(withSleep));

        JsonNode trophies = ok(getAs(me, "/profile/get-trophies").param("username", me.name()));
        assertThat(trophies.toString()).doesNotContain("sleep-");

        // one from each category: goals, calendar, budget, groceries, nutrition
        for (String id : List.of("weekly-goals-creator", "calendar-events-created", "watchlist-adder", "grocery-lists", "nutrition-logger")) {
            ok(as(me, post("/profile/increment-trophies").param("username", me.name()).param("trophyId", id).param("amount", "100")));
        }
        JsonNode allAround = null;
        for (JsonNode t : ok(getAs(me, "/profile/get-trophies").param("username", me.name()))) {
            if (t.get("id").asText().equals("all-around")) allAround = t;
        }
        assertThat(allAround).isNotNull();
        assertThat(allAround.get("level").asInt()).isEqualTo(4);
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
