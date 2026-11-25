package com.plotline.backend.afford;

import java.io.ByteArrayInputStream;
import java.util.Collection;
import java.util.Locale;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.plotline.backend.service.S3Service;

/**
 * "Can I afford it?" → pause a subscription while saving for something: it's marked paused in Track
 * Subscriptions (pausedFor: the goal), so it no longer counts toward their subscriptions, and resumes
 * when the goal ends (reached, bought or deleted). The budget's Subscriptions line follows through
 * the goal's cuts; what's charged follows by itself (a paused subscription isn't charged).
 */
@Component
public class SubscriptionPauses {
    private static final Logger log = LoggerFactory.getLogger(SubscriptionPauses.class);

    private final S3Service s3;
    private final ObjectMapper json = new ObjectMapper();

    public SubscriptionPauses(S3Service s3) {
        this.s3 = s3;
    }

    private static String key(String user) { return "users/%s/subscriptions.json".formatted(user); }

    /** @return the total monthly cost paused */
    public double pause(String user, Collection<String> names, String goalId, String goalName) {
        if (names.isEmpty()) return 0;
        Set<String> wanted = new java.util.HashSet<>();
        names.forEach(n -> wanted.add(n.strip().toLowerCase(Locale.ROOT)));
        ObjectNode root = read(user);
        double total = 0;
        for (JsonNode item : root.path("subscriptions")) {
            if (!(item instanceof ObjectNode sub) || !wanted.contains(sub.path("name").asText("").strip().toLowerCase(Locale.ROOT))) continue;
            if (sub.path("pausedFor").isTextual()) continue;
            sub.put("pausedFor", goalId);
            sub.put("pausedForName", goalName);
            total += cost(sub);
        }
        if (total > 0) write(user, root);
        return total;
    }

    /** the goals that ended: their subscriptions resume */
    public void resume(String user, Set<String> endedGoalIds) {
        if (endedGoalIds.isEmpty()) return;
        ObjectNode root = read(user);
        double total = 0;
        for (JsonNode item : root.path("subscriptions")) {
            if (!(item instanceof ObjectNode sub) || !endedGoalIds.contains(sub.path("pausedFor").asText(null))) continue;
            sub.remove("pausedFor");
            sub.remove("pausedForName");
            total += cost(sub);
        }
        if (total > 0) write(user, root);
    }

    static double cost(JsonNode sub) {
        try {
            return Double.parseDouble(sub.path("cost").asText("0").replace("$", "").replace(",", "").strip());
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private ObjectNode read(String user) {
        try {
            byte[] data = s3.downloadFile(key(user));
            JsonNode n = data == null || data.length == 0 ? null : json.readTree(data);
            return n instanceof ObjectNode o ? o : json.createObjectNode();
        } catch (Exception e) {
            return json.createObjectNode();
        }
    }

    private void write(String user, ObjectNode root) {
        try {
            byte[] bytes = json.writeValueAsBytes(root);
            s3.uploadFile(key(user), new ByteArrayInputStream(bytes), bytes.length);
        } catch (Exception e) {
            log.warn("Couldn't save paused subscriptions for {}: {}", user, e.getMessage());
        }
    }
}
