package com.plotline.backend.dto;

import java.util.List;

public class RecurringChargeRequest {
    private String username;
    private Integer remindAfterMonths; // optional override
    private List<ChargeEvent> charges;

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public Integer getRemindAfterMonths() { return remindAfterMonths; }
    public void setRemindAfterMonths(Integer remindAfterMonths) { this.remindAfterMonths = remindAfterMonths; }

    public List<ChargeEvent> getCharges() { return charges; }
    public void setCharges(List<ChargeEvent> charges) { this.charges = charges; }

    public static class ChargeEvent {
        private String name;
        private Double amount;
        private String date; // ISO yyyy-MM-dd

        public ChargeEvent() {}
        public ChargeEvent(String name, Double amount, String date) {
            this.name = name;
            this.amount = amount;
            this.date = date;
        }

        public String getName() { return name; }
        public void setName(String name) { this.name = name; }

        public Double getAmount() { return amount; }
        public void setAmount(Double amount) { this.amount = amount; }

        public String getDate() { return date; }
        public void setDate(String date) { this.date = date; }
    }
}
