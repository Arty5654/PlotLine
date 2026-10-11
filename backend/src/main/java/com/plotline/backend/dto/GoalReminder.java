package com.plotline.backend.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * One reminder on a weekly goal. The phone schedules it; the server only keeps it with the goal
 * so it comes back on a new phone. Times are the user's local time.
 *
 * kind: "dueDate", "dayBefore", "weekBefore" (relative to the goal's due date) or "custom"
 * time: "HH:mm"
 * date: "yyyy-MM-dd", only for "custom"
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public class GoalReminder {
  private String id;
  private String kind;
  private String time;
  private String date;

  public GoalReminder() {
  }

  public String getId() { return id; }
  public void setId(String id) { this.id = id; }

  public String getKind() { return kind; }
  public void setKind(String kind) { this.kind = kind; }

  public String getTime() { return time; }
  public void setTime(String time) { this.time = time; }

  public String getDate() { return date; }
  public void setDate(String date) { this.date = date; }
}
