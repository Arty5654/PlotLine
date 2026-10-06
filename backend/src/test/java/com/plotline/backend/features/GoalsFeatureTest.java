package com.plotline.backend.features;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/** Goals page: weekly to-dos and long-term goals with steps. */
class GoalsFeatureTest extends FeatureTestBase {

    private JsonNode weekly(User user) throws Exception {
        return ok(getAs(user, "/api/goals/{u}", user.name())).get("weeklyGoals");
    }

    private JsonNode longTerm(User user) throws Exception {
        return ok(getAs(user, "/api/goals/{u}/long-term", user.name()));
    }

    private Map<String, Object> task(int id, String name) {
        return Map.of("id", id, "name", name, "isCompleted", false, "priority", "High",
                "notificationsEnabled", false, "dueDate", "2026-10-12");
    }

    @Test
    @DisplayName("Weekly goals: add, complete, delete, reset")
    void weeklyGoals() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/goals/" + me.name(), task(1, "Gym 3x")));
        ok(postJson(me, "/api/goals/" + me.name(), task(2, "Call mom")));
        assertThat(weekly(me)).hasSize(2);

        ok(putJson(me, "/api/goals/" + me.name() + "/2/completion", Map.of("isCompleted", true)));
        JsonNode callMom = null;
        for (JsonNode t : weekly(me)) if (t.get("id").asInt() == 2) callMom = t;
        assertThat(callMom.toString()).containsAnyOf("\"completed\":true", "\"isCompleted\":true");

        ok(deleteAs(me, "/api/goals/{u}/{id}", me.name(), 1));
        assertThat(weekly(me)).hasSize(1);

        ok(deleteAs(me, "/api/goals/{u}/reset", me.name()));
        assertThat(weekly(me)).isEmpty();
    }

    @Test
    @Disabled("Known bug: BUGS.md #4 (editing a weekly goal with a due date fails)")
    @DisplayName("Editing a weekly goal saves the change")
    void editWeeklyGoal() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/goals/" + me.name(), task(1, "Gym 3x")));

        ok(putJson(me, "/api/goals/" + me.name() + "/1", task(1, "Gym 4x")));

        assertThat(weekly(me).toString()).contains("Gym 4x");
    }

    @Test
    @DisplayName("Long-term goals: add with steps, tick a step, archive and unarchive, reset")
    void longTermGoals() throws Exception {
        User me = newUser();
        UUID goalId = UUID.randomUUID();
        UUID stepId = UUID.randomUUID();
        ok(postJson(me, "/api/goals/" + me.name() + "/long-term", Map.of("id", goalId.toString(),
                "title", "Emergency fund", "steps", List.of(
                        Map.of("id", stepId.toString(), "name", "Save $500", "isCompleted", false),
                        Map.of("id", UUID.randomUUID().toString(), "name", "Save $1000", "isCompleted", false)))));
        assertThat(longTerm(me).get("longTermGoals").toString()).contains("Emergency fund");

        ok(putJson(me, "/api/goals/" + me.name() + "/long-term/" + goalId + "/steps/" + stepId,
                Map.of("isCompleted", true)));
        assertThat(longTerm(me).get("longTermGoals").toString())
                .containsAnyOf("\"completed\":true", "\"isCompleted\":true");

        ok(as(me, org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                .put("/api/goals/{u}/long-term/{g}/archive", me.name(), goalId)));
        assertThat(longTerm(me).get("longTermGoals").toString()).doesNotContain("Emergency fund");
        assertThat(longTerm(me).get("archivedGoals").toString()).contains("Emergency fund");

        ok(as(me, org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                .put("/api/goals/{u}/long-term/{g}/unarchive", me.name(), goalId)));
        assertThat(longTerm(me).get("longTermGoals").toString()).contains("Emergency fund");

        ok(deleteAs(me, "/api/goals/{u}/long-term/reset", me.name()));
        assertThat(longTerm(me).get("longTermGoals")).isEmpty();
    }

    @Test
    @DisplayName("Another user's goals are off limits")
    void ownGoalsOnly() throws Exception {
        User me = newUser();
        User other = newUser();
        call(getAs(me, "/api/goals/{u}", other.name()), 403);
        call(postJson(me, "/api/goals/" + other.name(), task(1, "Planted")), 403);
    }
}
