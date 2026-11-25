package com.plotline.backend.dto;

import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.annotation.JsonFormat;
import java.util.Date;

public class SubscriptionRequest {
    private String username;
    private Map<String, SubscriptionItem> subscriptions;

    public static class SubscriptionItem {
        private String name;
        private String cost; // optional/nullable; kept for backward compatibility

        //@JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd'T'HH:mm:ss'Z'", timezone = "EST")
        @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", timezone = "UTC")
        private Date dueDate;

        /** "Can I afford it?": paused while saving for this goal (its id), resumed when the goal ends */
        private String pausedFor;
        private String pausedForName;

        // Constructors
        public SubscriptionItem() {}

        public SubscriptionItem(String name, String cost, Date dueDate) {
            this.name = name;
            this.cost = cost;
            this.dueDate = dueDate;
        }

        public String getName() { return name; }
        public void setName(String name) { this.name = name; }

        public String getCost() { return cost; }
        public void setCost(String cost) { this.cost = cost; }

        public Date getDueDate() { return dueDate; }
        public void setDueDate(Date dueDate) { this.dueDate = dueDate; }

        public String getPausedFor() { return pausedFor; }
        public void setPausedFor(String pausedFor) { this.pausedFor = pausedFor; }

        public String getPausedForName() { return pausedForName; }
        public void setPausedForName(String pausedForName) { this.pausedForName = pausedForName; }
    }

    // Constructors
    public SubscriptionRequest() {}

    public SubscriptionRequest(String username, Map<String, SubscriptionItem> subscriptions) {
        this.username = username;
        this.subscriptions = subscriptions;
    }

    // Getters & Setters
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public Map<String, SubscriptionItem> getSubscriptions() { return subscriptions; }
    public void setSubscriptions(Map<String, SubscriptionItem> subscriptions) {
        this.subscriptions = subscriptions;
    }
}
