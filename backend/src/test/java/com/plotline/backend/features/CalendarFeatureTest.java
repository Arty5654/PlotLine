package com.plotline.backend.features;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/** Calendar page: your events, inviting friends, and sharing calendars with friends. */
class CalendarFeatureTest extends FeatureTestBase {

    private Map<String, Object> event(String owner, String title) {
        Map<String, Object> event = new HashMap<>();
        event.put("username", owner);
        event.put("id", UUID.randomUUID().toString());
        event.put("title", title);
        event.put("description", "");
        event.put("startDate", "2026-10-10T18:00:00Z");
        event.put("endDate", "2026-10-10T19:00:00Z");
        event.put("eventType", "user");
        event.put("recurrence", "none");
        event.put("invitedFriends", new ArrayList<>());
        event.put("friendsCanSee", true);
        return event;
    }

    private JsonNode events(User user) throws Exception {
        JsonNode response = ok(getAs(user, "/calendar/get-events").param("username", user.name()));
        assertThat(response.get("success").asBoolean()).isTrue();
        return response.get("events");
    }

    private JsonNode find(JsonNode events, String id) {
        for (JsonNode e : events) if (id.equals(e.path("id").asText())) return e;
        return null;
    }

    @Test
    @DisplayName("Create, read, edit and delete your own event")
    void ownEventLifecycle() throws Exception {
        User me = newUser();
        Map<String, Object> dinner = event(me.name(), "Dinner");
        String id = (String) dinner.get("id");

        JsonNode created = ok(postJson(me, "/calendar/create-event", dinner));
        assertThat(created.get("success").asBoolean()).isTrue();
        assertThat(find(events(me), id).get("title").asText()).isEqualTo("Dinner");

        dinner.put("title", "Late dinner");
        ok(postJson(me, "/calendar/update-event", dinner));
        assertThat(find(events(me), id).get("title").asText()).isEqualTo("Late dinner");

        ok(postJson(me, "/calendar/delete-event", Map.of("username", me.name(), "eventId", id)));
        assertThat(find(events(me), id)).isNull();
    }

    @Test
    @DisplayName("Delete all events of one type (e.g. imported subscriptions) leaves the rest")
    void deleteByType() throws Exception {
        User me = newUser();
        Map<String, Object> keep = event(me.name(), "Keep me");
        ok(postJson(me, "/calendar/create-event", keep));
        Map<String, Object> gcal = event(me.name(), "From Google");
        gcal.put("eventType", "gcal");
        ok(postJson(me, "/calendar/batch-sync-gcal", Map.of("username", me.name(), "events", List.of(gcal))));
        assertThat(find(events(me), (String) gcal.get("id"))).isNotNull();

        ok(as(me, org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete("/calendar/delete-by-type"))
                .param("username", me.name()).param("type", "gcal"));

        assertThat(find(events(me), (String) gcal.get("id"))).isNull();
        assertThat(find(events(me), (String) keep.get("id"))).isNotNull();
    }

    @Test
    @DisplayName("Invite a friend: they get a pending invite; accepting updates your RSVP list")
    void inviteFriendAccept() throws Exception {
        User me = newUser();
        User friend = newUser();
        befriend(me, friend);

        Map<String, Object> party = event(me.name(), "Party");
        party.put("invitedFriends", new ArrayList<>(List.of(friend.name())));
        String id = (String) party.get("id");
        ok(postJson(me, "/calendar/create-event", party));

        JsonNode invite = find(events(friend), id);
        assertThat(invite.get("status").asText()).isEqualTo("invite-pending");
        assertThat(invite.get("addedBy").asText()).isEqualTo(me.name());

        ok(postJson(friend, "/calendar/respond-event-invite",
                Map.of("username", friend.name(), "eventId", id, "accept", true)));

        assertThat(find(events(friend), id).get("status").asText()).isEqualTo("accepted");
        assertThat(find(events(me), id).get("inviteStatuses").get(friend.name()).asText()).isEqualTo("accepted");
    }

    @Test
    @DisplayName("Declining an invite removes it from your calendar and tells the host")
    void inviteFriendDecline() throws Exception {
        User me = newUser();
        User friend = newUser();
        befriend(me, friend);
        Map<String, Object> party = event(me.name(), "Party");
        party.put("invitedFriends", new ArrayList<>(List.of(friend.name())));
        String id = (String) party.get("id");
        ok(postJson(me, "/calendar/create-event", party));

        ok(postJson(friend, "/calendar/respond-event-invite",
                Map.of("username", friend.name(), "eventId", id, "accept", false)));

        assertThat(find(events(friend), id)).isNull();
        assertThat(find(events(me), id).get("inviteStatuses").get(friend.name()).asText()).isEqualTo("declined");
    }

    @Test
    @DisplayName("Calendar sharing: no access shows nothing; after accepting 'view' access you see visible events")
    void viewSharing() throws Exception {
        User owner = newUser();
        User viewer = newUser();
        befriend(owner, viewer);
        Map<String, Object> visible = event(owner.name(), "Visible");
        Map<String, Object> hidden = event(owner.name(), "Private");
        hidden.put("friendsCanSee", false);
        ok(postJson(owner, "/calendar/create-event", visible));
        ok(postJson(owner, "/calendar/create-event", hidden));

        JsonNode before = ok(getAs(viewer, "/calendar-access/shared-events")
                .param("ownerUsername", owner.name()).param("requesterUsername", viewer.name()));
        assertThat(before).isEmpty();

        JsonNode invite = ok(postJson(owner, "/calendar-access/send-invite",
                Map.of("fromUsername", owner.name(), "toUsername", viewer.name(), "level", "view", "requireApproval", false)));
        JsonNode incoming = ok(getAs(viewer, "/calendar-access/data").param("username", viewer.name())).get("pendingIncoming");
        assertThat(incoming).hasSize(1);
        ok(postJson(viewer, "/calendar-access/respond-invite",
                Map.of("recipientUsername", viewer.name(), "inviteId", invite.get("id").asText(), "accept", true)));

        JsonNode after = ok(getAs(viewer, "/calendar-access/shared-events")
                .param("ownerUsername", owner.name()).param("requesterUsername", viewer.name()));
        assertThat(after).hasSize(1);
        assertThat(after.get(0).get("title").asText()).isEqualTo("Visible");

        // revoking access hides it again
        ok(postJson(owner, "/calendar-access/revoke",
                Map.of("ownerUsername", owner.name(), "friendUsername", viewer.name(), "keepEvents", true)));
        assertThat(ok(getAs(viewer, "/calendar-access/shared-events")
                .param("ownerUsername", owner.name()).param("requesterUsername", viewer.name()))).isEmpty();
    }

    @Test
    @DisplayName("'Add' access with approval: a friend's event waits as pending until the owner approves")
    void addAccessWithApproval() throws Exception {
        User owner = newUser();
        User friend = newUser();
        befriend(owner, friend);
        JsonNode invite = ok(postJson(owner, "/calendar-access/send-invite",
                Map.of("fromUsername", owner.name(), "toUsername", friend.name(), "level", "add", "requireApproval", true)));
        ok(postJson(friend, "/calendar-access/respond-invite",
                Map.of("recipientUsername", friend.name(), "inviteId", invite.get("id").asText(), "accept", true)));

        Map<String, Object> suggestion = event(owner.name(), "Study group");
        suggestion.put("addedBy", friend.name());
        String id = (String) suggestion.get("id");
        ok(postJson(friend, "/calendar/create-event", suggestion));
        assertThat(find(events(owner), id).get("status").asText()).isEqualTo("pending");

        ok(postJson(owner, "/calendar-access/approve-event", Map.of("ownerUsername", owner.name(), "eventId", id)));
        assertThat(find(events(owner), id).get("status").asText()).isEqualTo("approved");
    }

    @Test
    @DisplayName("Rejecting a friend's suggested event removes it")
    void rejectSuggestedEvent() throws Exception {
        User owner = newUser();
        User friend = newUser();
        befriend(owner, friend);
        JsonNode invite = ok(postJson(owner, "/calendar-access/send-invite",
                Map.of("fromUsername", owner.name(), "toUsername", friend.name(), "level", "add", "requireApproval", true)));
        ok(postJson(friend, "/calendar-access/respond-invite",
                Map.of("recipientUsername", friend.name(), "inviteId", invite.get("id").asText(), "accept", true)));
        Map<String, Object> suggestion = event(owner.name(), "Spam");
        suggestion.put("addedBy", friend.name());
        ok(postJson(friend, "/calendar/create-event", suggestion));

        ok(postJson(owner, "/calendar-access/reject-event",
                Map.of("ownerUsername", owner.name(), "eventId", suggestion.get("id"))));

        assertThat(find(events(owner), (String) suggestion.get("id"))).isNull();
    }

    @Test
    @DisplayName("Without 'add' access you can't put events on someone's calendar")
    void noAddAccess() throws Exception {
        User owner = newUser();
        User stranger = newUser();
        Map<String, Object> sneaky = event(owner.name(), "Sneaky");
        sneaky.put("addedBy", stranger.name());

        call(postJson(stranger, "/calendar/create-event", sneaky), 403);
        assertThat(find(events(owner), (String) sneaky.get("id"))).isNull();
    }

    @Test
    @DisplayName("Only friends get event invites; strangers are dropped and no placeholder is saved (BUGS.md #2, #3)")
    void invitesOnlyFriends() throws Exception {
        User me = newUser();
        User friend = newUser();
        User stranger = newUser();
        befriend(me, friend);
        Map<String, Object> party = event(me.name(), "Party");
        party.put("invitedFriends", new ArrayList<>(List.of(friend.name(), stranger.name(), me.name())));
        String id = (String) party.get("id");

        ok(postJson(me, "/calendar/create-event", party));

        assertThat(find(events(friend), id)).isNotNull();
        assertThat(find(events(stranger), id)).isNull();
        assertThat(find(events(me), id).get("invitedFriends").toString()).isEqualTo("[\"" + friend.name() + "\"]");
    }

    @Test
    @DisplayName("Editing an event can't invite strangers either")
    void editInvitesOnlyFriends() throws Exception {
        User me = newUser();
        User friend = newUser();
        User stranger = newUser();
        befriend(me, friend);
        Map<String, Object> party = event(me.name(), "Party");
        party.put("invitedFriends", new ArrayList<>(List.of(friend.name())));
        String id = (String) party.get("id");
        ok(postJson(me, "/calendar/create-event", party));

        party.put("invitedFriends", new ArrayList<>(List.of(friend.name(), stranger.name())));
        ok(postJson(me, "/calendar/update-event", party));

        assertThat(find(events(stranger), id)).isNull();
        assertThat(find(events(me), id).get("invitedFriends").toString()).isEqualTo("[\"" + friend.name() + "\"]");
    }

    @Test
    @DisplayName("Events saved with the old placeholder come back without it")
    void oldPlaceholderStripped() throws Exception {
        User me = newUser();
        Map<String, Object> dinner = event(me.name(), "Dinner");
        String id = (String) dinner.get("id");
        ok(postJson(me, "/calendar/create-event", dinner));
        String key = "users/" + me.name() + "/calendar.json";
        String stored = new String(s3.getObjectAsBytes(b -> b.bucket("plotline-database-bucket").key(key)).asByteArray(),
                java.nio.charset.StandardCharsets.UTF_8);
        assertThat(stored).contains("\"invitedFriends\":[]"); // so the placeholder really gets injected below
        s3.putObject(b -> b.bucket("plotline-database-bucket").key(key), software.amazon.awssdk.core.sync.RequestBody.fromString(
                stored.replace("\"invitedFriends\":[]", "\"invitedFriends\":[\"c-123-creator-user-c-987\"]")));

        assertThat(find(events(me), id).get("invitedFriends").toString()).isEqualTo("[]");
    }

    @Test
    @DisplayName("Removing a friend removes their event invites from both calendars")
    void unfriendRemovesInvites() throws Exception {
        User me = newUser();
        User friend = newUser();
        befriend(me, friend);
        Map<String, Object> party = event(me.name(), "Party");
        party.put("invitedFriends", new ArrayList<>(List.of(friend.name())));
        ok(postJson(me, "/calendar/create-event", party));

        ok(postJson(me, "/friends/remove",
                Map.of("senderUsername", me.name(), "receiverUsername", friend.name(), "status", "REMOVE")));

        assertThat(find(events(friend), (String) party.get("id"))).isNull();
    }
}
