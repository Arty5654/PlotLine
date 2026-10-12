package com.plotline.backend.features;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

import java.time.ZonedDateTime;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;

import com.plotline.backend.push.PushService;
import com.plotline.backend.push.WeeklyRecapService;

/** Push notifications: which phones get them, what sends them, and the weekly recap. */
class PushFeatureTest extends FeatureTestBase {

    @Autowired JdbcTemplate jdbc;
    @Autowired WeeklyRecapService recaps;

    private static final String TOKEN = "a".repeat(64);

    private static org.mockito.ArgumentMatcher<PushService.Message> says(String text) {
        return m -> m != null && (m.title() + " " + m.body()).contains(text);
    }

    @Test
    @DisplayName("A phone registers for the signed-in account; a phone belongs to whoever signed in last; signing out removes it")
    void devices() throws Exception {
        User me = newUser();
        User other = newUser();
        ok(postJson(me, "/api/push/devices", Map.of("token", TOKEN, "environment", "sandbox", "timeZone", "America/Chicago")));
        assertThat(jdbc.queryForObject("select username from push_devices where token = ?", String.class, TOKEN))
                .isEqualTo(me.name().toLowerCase());

        ok(postJson(other, "/api/push/devices", Map.of("token", TOKEN, "environment", "production", "timeZone", "UTC")));
        assertThat(jdbc.queryForObject("select username from push_devices where token = ?", String.class, TOKEN))
                .isEqualTo(other.name().toLowerCase());

        ok(deleteAs(other, "/api/push/devices").param("token", TOKEN));
        assertThat(jdbc.queryForObject("select count(*) from push_devices where token = ?", Integer.class, TOKEN)).isZero();

        call(postJson(me, "/api/push/devices", Map.of("token", "not a token")), 400);
    }

    @Test
    @DisplayName("Friend requests, accepted requests, list shares, calendar invites and invite answers send pushes")
    void triggers() throws Exception {
        User me = newUser();
        User friend = newUser();
        befriend(me, friend);
        verify(pushService).send(eq(friend.name().toLowerCase()), argThat(says("wants to be friends")));
        verify(pushService).send(eq(me.name().toLowerCase()), argThat(says("accepted your friend request")));

        // calendar: invite to an event, then they accept
        Map<String, Object> party = new java.util.HashMap<>(Map.of("username", me.name(), "id", java.util.UUID.randomUUID().toString(),
                "title", "Game night", "description", "", "startDate", "2026-10-10T18:00:00Z", "endDate", "2026-10-10T19:00:00Z",
                "eventType", "user", "recurrence", "none", "friendsCanSee", true));
        party.put("invitedFriends", List.of(friend.name()));
        ok(postJson(me, "/calendar/create-event", party));
        verify(pushService).send(eq(friend.name().toLowerCase()), argThat(says("invited you to \"Game night\"")));
        ok(postJson(friend, "/calendar/respond-event-invite", Map.of("username", friend.name(), "eventId", party.get("id"), "accept", true)));
        verify(pushService).send(eq(me.name().toLowerCase()), argThat(says("is going to \"Game night\"")));

        // calendar sharing invite
        ok(postJson(me, "/calendar-access/send-invite", Map.of("fromUsername", me.name(), "toUsername", friend.name(),
                "level", "view", "requireApproval", false)));
        verify(pushService).send(eq(friend.name().toLowerCase()), argThat(says("wants to share calendars")));
    }

    @Test
    @DisplayName("Weekly recap: Sunday 6-8 PM in the person's time zone, once per week, with this week's spending vs budget")
    void weeklyRecap() throws Exception {
        User me = newUser();
        String user = me.name().toLowerCase();
        ok(postJson(me, "/api/push/devices", Map.of("token", "b".repeat(64), "environment", "sandbox", "timeZone", "America/New_York")));
        // weekly budget (savings isn't spending) and this week's spending
        s3.putObject(b -> b.bucket("plotline-database-bucket").key("users/" + user + "/weekly-budget.json"),
                software.amazon.awssdk.core.sync.RequestBody.fromString("{\"Groceries\": 100, \"Eating Out\": 50, \"Savings\": 200}"));
        s3.putObject(b -> b.bucket("plotline-database-bucket").key("users/" + user + "/costs/weekly/2026-W42.json"),
                software.amazon.awssdk.core.sync.RequestBody.fromString("{\"totals\": {\"Groceries\": 80, \"Eating Out\": 40}}"));

        // Sunday Oct 11 2026, 5 PM in New York: too early
        recaps.run(ZonedDateTime.parse("2026-10-11T21:00:00Z"));
        org.mockito.Mockito.verify(pushService, org.mockito.Mockito.never()).send(eq(user), argThat(says("this week")));

        // 6:30 PM: sent; the next run at 7 PM doesn't send it again
        recaps.run(ZonedDateTime.parse("2026-10-11T22:30:00Z"));
        recaps.run(ZonedDateTime.parse("2026-10-11T23:00:00Z"));
        verify(pushService).send(eq(user), argThat(says("You spent $120 of your $150 budget this week. $30 left to spare.")));
    }

    @Test
    @DisplayName("The recap timer needs the secret token")
    void recapEndpointIsProtected() throws Exception {
        assertThat(mockMvc.perform(withKey(post("/internal/weekly-recap"))).andReturn().getResponse().getStatus()).isEqualTo(403);
        assertThat(mockMvc.perform(post("/internal/weekly-recap").header("X-Cron-Token", "guess")).andReturn().getResponse().getStatus())
                .isEqualTo(403);
    }
}
