package com.plotline.backend.service;

import java.io.ByteArrayInputStream;
import java.time.LocalDate;
import java.util.Map;

import org.springframework.stereotype.Component;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * When someone's budget last changed (the quiz, Regenerate, an edit, Revert, an applied tune):
 * "Tune your budget" only compares spending from whole months that started after it, so it doesn't
 * judge a brand-new budget by months from before it existed. users/<u>/budget-changed.json
 * A change to its categories also sorts recent bank transactions again (TransactionResorter).
 */
@Component
public class BudgetChanges {

    private final S3Service s3;
    private final com.plotline.backend.costs.TransactionResorter resorter;
    private final ObjectMapper json = new ObjectMapper();

    public BudgetChanges(S3Service s3, @org.springframework.context.annotation.Lazy com.plotline.backend.costs.TransactionResorter resorter) {
        this.s3 = s3;
        this.resorter = resorter;
    }

    private static String key(String username) {
        return "users/" + username.toLowerCase() + "/budget-changed.json";
    }

    public void record(String username) {
        try {
            byte[] bytes = json.writeValueAsBytes(Map.of("date", LocalDate.now().toString()));
            s3.uploadFile(key(username), new ByteArrayInputStream(bytes), bytes.length);
        } catch (Exception ignored) {
            // not worth failing a save over
        }
        // categories added or removed: bank transactions already in Monthly Costs move to the right ones
        resorter.afterBudgetChange(username);
    }

    /** the day it last changed, or null if that wasn't recorded (budgets from before this) */
    public LocalDate lastChange(String username) {
        try {
            Map<String, Object> saved = json.readValue(s3.downloadFile(key(username)), new TypeReference<Map<String, Object>>() {});
            return LocalDate.parse(String.valueOf(saved.get("date")));
        } catch (Exception e) {
            return null;
        }
    }
}
