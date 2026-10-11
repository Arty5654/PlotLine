package com.plotline.backend.features;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

/** Friends page: requests, friend list, goal feed, and chat. */
class FriendsFeatureTest extends FeatureTestBase {

    private JsonNode friendsOf(User user) throws Exception {
        return ok(getAs(user, "/friends/get-friends").param("username", user.name())).get("friends");
    }

    private JsonNode requestsOf(User user) throws Exception {
        return ok(getAs(user, "/friends/get-friend-requests").param("username", user.name())).get("pendingRequests");
    }

    @Test
    @DisplayName("Send, accept, and remove a friend")
    void requestAcceptRemove() throws Exception {
        User me = newUser();
        User them = newUser();
        ok(putJson(me, "/friends/request", Map.of("senderUsername", me.name(), "receiverUsername", them.name(), "status", "PENDING")));
        assertThat(requestsOf(them).toString()).contains(me.name());

        ok(putJson(them, "/friends/request", Map.of("senderUsername", me.name(), "receiverUsername", them.name(), "status", "ACCEPTED")));
        assertThat(friendsOf(me).toString()).contains(them.name());
        assertThat(friendsOf(them).toString()).contains(me.name());
        assertThat(requestsOf(them)).isEmpty();

        ok(postJson(me, "/friends/remove", Map.of("senderUsername", me.name(), "receiverUsername", them.name(), "status", "REMOVE")));
        assertThat(friendsOf(me)).isEmpty();
        assertThat(friendsOf(them)).isEmpty();
    }

    @Test
    @DisplayName("Declining a request removes it without becoming friends")
    void decline() throws Exception {
        User me = newUser();
        User them = newUser();
        ok(putJson(me, "/friends/request", Map.of("senderUsername", me.name(), "receiverUsername", them.name(), "status", "PENDING")));
        ok(putJson(them, "/friends/request", Map.of("senderUsername", me.name(), "receiverUsername", them.name(), "status", "DECLINED")));

        assertThat(requestsOf(them)).isEmpty();
        assertThat(friendsOf(me)).isEmpty();
    }

    @Test
    @DisplayName("Search: user-exists, and searching usernames (the app no longer gets every username)")
    void search() throws Exception {
        User me = newUser();
        User them = newUser();
        assertThat(ok(getAs(me, "/auth/user-exists").param("username", them.name())).asBoolean()).isTrue();
        assertThat(ok(getAs(me, "/auth/user-exists").param("username", "nobody" + UUID.randomUUID().toString().substring(0, 6))).asBoolean()).isFalse();

        String middle = them.name().substring(3, 9);
        assertThat(ok(getAs(me, "/auth/search-users").param("q", middle)).toString()).contains(them.name());
        assertThat(ok(getAs(me, "/auth/search-users").param("q", me.name())).toString()).doesNotContain(me.name()); // not yourself
        assertThat(ok(getAs(me, "/auth/search-users").param("q", "%_'")).size()).isZero();
        call(getAs(me, "/auth/get-users"), 404);
    }

    @Test
    @DisplayName("Goal feed: friends see your posts and can like and comment; strangers don't see them")
    void goalFeed() throws Exception {
        User me = newUser();
        User friend = newUser();
        User stranger = newUser();
        befriend(me, friend);
        String postId = UUID.randomUUID().toString();
        Map<String, Object> goal = Map.of("id", UUID.randomUUID().toString(), "title", "Run a 5k", "steps", List.of());
        ok(postJson(me, "/api/goals/friends-feed/" + me.name() + "/post", Map.of("id", postId, "username", me.name(),
                "goal", goal, "comment", "Ran my first 5k!", "likedBy", List.of(), "comments", List.of())));

        JsonNode friendFeed = ok(getAs(friend, "/api/goals/friends-feed/{u}", friend.name()));
        assertThat(friendFeed.toString()).contains("Ran my first 5k!");
        assertThat(ok(getAs(stranger, "/api/goals/friends-feed/{u}", stranger.name())).toString()).doesNotContain("Ran my first 5k!");

        ok(as(friend, put("/api/goals/friends-feed/{u}/post/{p}/like", friend.name(), postId)));
        ok(json(friend, post("/api/goals/friends-feed/{u}/post/{p}/comment", friend.name(), postId), Map.of("comment", "Nice!")));
        String mine = ok(getAs(me, "/api/goals/friends-feed/{u}", me.name())).toString();
        assertThat(mine).contains(friend.name()).contains("Nice!");

        ok(deleteAs(me, "/api/goals/friends-feed/{u}/post/{p}", me.name(), postId));
        assertThat(ok(getAs(friend, "/api/goals/friends-feed/{u}", friend.name())).toString()).doesNotContain("Ran my first 5k!");
    }

    @Test
    @DisplayName("Goal feed: a weekly goal can be shared with a note; a post without a goal is refused")
    void shareWeeklyGoal() throws Exception {
        User me = newUser();
        User friend = newUser();
        befriend(me, friend);
        Map<String, Object> weekly = Map.of("name", "Gym 3x", "priority", "High", "dueDate", "2026-10-12", "completed", true);
        ok(postJson(me, "/api/goals/friends-feed/" + me.name() + "/post", Map.of("id", UUID.randomUUID().toString(),
                "username", me.name(), "weeklyGoal", weekly, "comment", "Done early!")));

        JsonNode post = null;
        for (JsonNode p : ok(getAs(friend, "/api/goals/friends-feed/{u}", friend.name()))) {
            if (p.path("weeklyGoal").path("name").asText().equals("Gym 3x")) post = p;
        }
        assertThat(post).isNotNull();
        assertThat(post.get("comment").asText()).isEqualTo("Done early!");
        assertThat(post.get("weeklyGoal").get("completed").asBoolean()).isTrue();
        assertThat(post.get("weeklyGoal").get("dueDate").asText()).isEqualTo("2026-10-12");
        assertThat(post.get("goal").get("title").asText()).isEqualTo("Gym 3x"); // for older app versions
        assertThat(post.get("goal").get("steps")).isEmpty();

        call(postJson(me, "/api/goals/friends-feed/" + me.name() + "/post", Map.of("id", UUID.randomUUID().toString(),
                "username", me.name(), "comment", "nothing to show")), 400);
    }

    @Test
    @DisplayName("Goal feed: a post shared with chosen friends is seen only by them; only the author sees who it went to")
    void shareWithChosenFriends() throws Exception {
        User me = newUser();
        User chosen = newUser();
        User other = newUser();
        befriend(me, chosen);
        befriend(me, other);
        Map<String, Object> goal = Map.of("id", UUID.randomUUID().toString(), "title", "Secret plan", "steps", List.of());
        ok(postJson(me, "/api/goals/friends-feed/" + me.name() + "/post", Map.of("id", UUID.randomUUID().toString(),
                "username", me.name(), "goal", goal, "audience", List.of(chosen.name().toUpperCase()))));

        JsonNode chosenFeed = ok(getAs(chosen, "/api/goals/friends-feed/{u}", chosen.name()));
        assertThat(chosenFeed.toString()).contains("Secret plan");
        for (JsonNode p : chosenFeed) assertThat(p.get("audience").isNull()).isTrue();
        assertThat(ok(getAs(other, "/api/goals/friends-feed/{u}", other.name())).toString()).doesNotContain("Secret plan");

        JsonNode mine = ok(getAs(me, "/api/goals/friends-feed/{u}", me.name()));
        assertThat(mine.toString()).contains("Secret plan");
        assertThat(mine.get(0).get("audience").get(0).asText()).isEqualTo(chosen.name());
    }

    @Test
    @DisplayName("Chat: post a message, friends see it, react and reply")
    void chat() throws Exception {
        User me = newUser();
        User friend = newUser();
        befriend(me, friend);

        JsonNode posted = ok(json(me, post("/chat").param("userId", me.name()), Map.of("content", "Hello friends")));
        String messageId = posted.get("id").asText();

        JsonNode friendFeed = ok(getAs(friend, "/chat/get-feed").param("userId", friend.name()));
        assertThat(friendFeed.toString()).contains("Hello friends");

        ok(json(friend, post("/chat/{o}/{m}/reactions", me.name(), messageId), Map.of("emoji", "🔥")));
        ok(json(friend, post("/chat/{o}/{m}/replies", me.name(), messageId), Map.of("userId", friend.name(), "text", "Hey!")));
        String after = ok(getAs(me, "/chat/get-feed").param("userId", me.name())).toString();
        assertThat(after).contains("Hey!");
    }
}
