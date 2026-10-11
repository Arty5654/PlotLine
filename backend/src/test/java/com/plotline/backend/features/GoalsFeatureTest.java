package com.plotline.backend.features;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.core.sync.RequestBody;

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
    @DisplayName("Reminders are saved with a weekly goal, can be changed, and survive completing it")
    void weeklyGoalReminders() throws Exception {
        User me = newUser();
        Map<String, Object> goal = new java.util.HashMap<>(task(7, "Dentist"));
        goal.put("reminders", List.of(
                Map.of("id", "r1", "kind", "dayBefore", "time", "18:30"),
                Map.of("id", "r2", "kind", "custom", "time", "08:00", "date", "2026-10-11")));
        ok(postJson(me, "/api/goals/" + me.name(), goal));

        JsonNode reminders = weekly(me).get(0).get("reminders");
        assertThat(reminders).hasSize(2);
        assertThat(reminders.get(0).get("kind").asText()).isEqualTo("dayBefore");
        assertThat(reminders.get(0).get("time").asText()).isEqualTo("18:30");
        assertThat(reminders.get(1).get("date").asText()).isEqualTo("2026-10-11");

        ok(putJson(me, "/api/goals/" + me.name() + "/7/completion", Map.of("isCompleted", true)));
        assertThat(weekly(me).get(0).get("reminders")).hasSize(2);

        goal.put("reminders", List.of(Map.of("id", "r3", "kind", "dueDate", "time", "09:00")));
        ok(putJson(me, "/api/goals/" + me.name() + "/7", goal));
        assertThat(weekly(me).get(0).get("reminders")).hasSize(1);

        Map<String, Object> plain = task(8, "No reminders");
        ok(postJson(me, "/api/goals/" + me.name(), plain));
        for (JsonNode t : weekly(me)) {
            if (t.get("id").asInt() == 8) assertThat(t.get("reminders")).isEmpty();
        }
    }

    private JsonNode step(User user, UUID goalId, UUID stepId) throws Exception {
        for (JsonNode g : longTerm(user).get("longTermGoals")) {
            if (g.get("id").asText().equals(goalId.toString())) {
                for (JsonNode st : g.get("steps")) if (st.get("id").asText().equals(stepId.toString())) return st;
            }
        }
        return null;
    }

    private JsonNode weeklyGoal(User user, int id) throws Exception {
        for (JsonNode t : weekly(user)) if (t.get("id").asInt() == id) return t;
        return null;
    }

    @Test
    @DisplayName("Long-term goals can be edited: title, target date, reminders and steps")
    void editLongTermGoal() throws Exception {
        User me = newUser();
        UUID goalId = UUID.randomUUID();
        ok(postJson(me, "/api/goals/" + me.name() + "/long-term", Map.of("id", goalId.toString(), "title", "Spanish",
                "steps", List.of(Map.of("id", UUID.randomUUID().toString(), "name", "Duolingo", "isCompleted", false)))));

        UUID newStep = UUID.randomUUID();
        ok(putJson(me, "/api/goals/" + me.name() + "/long-term/" + goalId, Map.of("id", goalId.toString(),
                "title", "Learn Spanish", "targetDate", "2027-03-01",
                "reminders", List.of(Map.of("id", "r1", "kind", "weekBefore", "time", "10:00")),
                "steps", List.of(Map.of("id", newStep.toString(), "name", "Take a class", "isCompleted", false)))));

        JsonNode goal = longTerm(me).get("longTermGoals").get(0);
        assertThat(goal.get("title").asText()).isEqualTo("Learn Spanish");
        assertThat(goal.get("targetDate").asText()).isEqualTo("2027-03-01");
        assertThat(goal.get("reminders").get(0).get("kind").asText()).isEqualTo("weekBefore");
        assertThat(goal.get("steps")).hasSize(1);
        assertThat(goal.get("steps").get(0).get("name").asText()).isEqualTo("Take a class");

        call(putJson(me, "/api/goals/" + me.name() + "/long-term/" + UUID.randomUUID(), Map.of("title", "Nope")), 404);
    }

    @Test
    @DisplayName("A step made into a weekly goal: checking off either one checks off both; deleting the weekly goal unlinks the step")
    void stepAsWeeklyGoal() throws Exception {
        User me = newUser();
        UUID goalId = UUID.randomUUID();
        UUID stepId = UUID.randomUUID();
        ok(postJson(me, "/api/goals/" + me.name() + "/long-term", Map.of("id", goalId.toString(), "title", "Emergency fund",
                "steps", List.of(Map.of("id", stepId.toString(), "name", "Save $500", "isCompleted", false),
                        Map.of("id", UUID.randomUUID().toString(), "name", "Save $1000", "isCompleted", false)))));

        Map<String, Object> weekly = new java.util.HashMap<>(task(55, "Save $500"));
        weekly.put("longTermGoalId", goalId.toString());
        weekly.put("longTermStepId", stepId.toString());
        ok(postJson(me, "/api/goals/" + me.name(), weekly));
        assertThat(step(me, goalId, stepId).get("weeklyGoalId").asInt()).isEqualTo(55);
        assertThat(weeklyGoal(me, 55).get("longTermStepId").asText()).isEqualTo(stepId.toString());

        ok(putJson(me, "/api/goals/" + me.name() + "/55/completion", Map.of("isCompleted", true)));
        assertThat(step(me, goalId, stepId).get("completed").asBoolean()).isTrue();

        ok(putJson(me, "/api/goals/" + me.name() + "/long-term/" + goalId + "/steps/" + stepId, Map.of("isCompleted", false)));
        assertThat(weeklyGoal(me, 55).get("completed").asBoolean()).isFalse();

        ok(deleteAs(me, "/api/goals/{u}/{id}", me.name(), 55));
        assertThat(step(me, goalId, stepId).get("weeklyGoalId").isNull()).isTrue();
        assertThat(step(me, goalId, stepId).get("completed").asBoolean()).isFalse(); // the step itself stays
    }

    private long chatCount(User user, String text) throws Exception {
        long n = 0;
        for (JsonNode m : ok(getAs(user, "/chat/get-feed").param("userId", user.name()))) {
            if (m.get("content").asText().equals(text)) n++;
        }
        return n;
    }

    @Test
    @DisplayName("Chat says a goal is completed only while it is: unchecking takes it back, re-checking doesn't repeat it")
    void completionMessagesFollowTheCheckmark() throws Exception {
        User me = newUser();
        ok(postJson(me, "/api/goals/" + me.name(), task(9, "Gym 3x")));
        String weekly = "Has completed \"Gym 3x\" from their weekly goals!";

        ok(putJson(me, "/api/goals/" + me.name() + "/9/completion", Map.of("isCompleted", true)));
        assertThat(chatCount(me, weekly)).isEqualTo(1);
        ok(putJson(me, "/api/goals/" + me.name() + "/9/completion", Map.of("isCompleted", false)));
        assertThat(chatCount(me, weekly)).isZero();
        ok(putJson(me, "/api/goals/" + me.name() + "/9/completion", Map.of("isCompleted", true)));
        ok(putJson(me, "/api/goals/" + me.name() + "/9/completion", Map.of("isCompleted", true)));
        assertThat(chatCount(me, weekly)).isEqualTo(1);

        UUID goalId = UUID.randomUUID();
        UUID a = UUID.randomUUID();
        UUID b = UUID.randomUUID();
        ok(postJson(me, "/api/goals/" + me.name() + "/long-term", Map.of("id", goalId.toString(), "title", "Spanish",
                "steps", List.of(Map.of("id", a.toString(), "name", "A", "isCompleted", false),
                        Map.of("id", b.toString(), "name", "B", "isCompleted", false)))));
        String longTerm = "Has completed the long-term goal \"Spanish\"!";
        ok(putJson(me, "/api/goals/" + me.name() + "/long-term/" + goalId + "/steps/" + a, Map.of("isCompleted", true)));
        assertThat(chatCount(me, longTerm)).isZero(); // one step left
        ok(putJson(me, "/api/goals/" + me.name() + "/long-term/" + goalId + "/steps/" + b, Map.of("isCompleted", true)));
        assertThat(chatCount(me, longTerm)).isEqualTo(1);
        ok(putJson(me, "/api/goals/" + me.name() + "/long-term/" + goalId + "/steps/" + b, Map.of("isCompleted", false)));
        assertThat(chatCount(me, longTerm)).isZero();
    }

    @Test
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
    @DisplayName("Savings goal: uses the quiz's budget when it hasn't been edited, and is empty with no budget")
    void financialSummary() throws Exception {
        User me = newUser();
        JsonNode empty = ok(getAs(me, "/api/goals/{u}/financial-data", me.name()));
        assertThat(empty.get("totalBudget").asDouble()).isZero();
        assertThat(empty.get("totalCosts").asDouble()).isZero();

        s3.putObject(b -> b.bucket("plotline-database-bucket").key("users/" + me.name() + "/weekly-budget.json"),
                RequestBody.fromString("{\"Groceries\": 80.0, \"Eating Out\": 40.5}"));
        assertThat(ok(getAs(me, "/api/goals/{u}/financial-data", me.name())).get("totalBudget").asDouble()).isEqualTo(120.5);
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
