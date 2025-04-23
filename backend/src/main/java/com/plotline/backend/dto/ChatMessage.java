package com.plotline.backend.dto;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
  
public class ChatMessage {
    private String id;
    private String creator; 
    private String timestamp;
    private String content;
    private Map<String, Integer> reactions = new HashMap<>();
    private Map<String, List<String>> replies  = new HashMap<>();


    public ChatMessage() {}

    public ChatMessage(String id, String creator, String timestamp, String content) {
        this.id = id;
        this.creator = creator;
        this.timestamp = timestamp;
        this.content = content;
    }

    public String getId() {
        return id;
    }
    public void setId(String id) {
        this.id = id;
    }

    public String getCreator() {
        return creator;
    }
    public void setCreator(String creator) {
        this.creator = creator;
    }

    public String getTimestamp() {
        return timestamp;
    }
    public void setTimestamp(String timestamp) {
        this.timestamp = timestamp;
    }

    public String getContent() {
        return content;
    }
    public void setContent(String content) {
        this.content = content;
    }

    public Map<String, Integer> getReactions() {
        return reactions;
    }
    public void setReactions(Map<String, Integer> reactions) {
        this.reactions = reactions;
    }

    public Map<String, List<String>> getReplies() {
        return replies;
    }
    public void setReplies(Map<String, List<String>> replies) {
        this.replies = replies;
    }

    public void addReaction(String emoji) {
      reactions.merge(emoji, 1, Integer::sum);
    }
    public void removeReaction(String emoji) {
      reactions.computeIfPresent(emoji, (e, count) -> {
          int updated = count - 1;
          return updated > 0 ? updated : null;
      });
    }

    public void addReply(String userId, String reply) {
        replies.computeIfAbsent(userId, k -> new java.util.ArrayList<>()).add(reply);
    }
    public void removeReply(String userId, String reply) {
        List<String> userReplies = replies.get(userId);
        if (userReplies != null) {
            userReplies.remove(reply);
            if (userReplies.isEmpty()) {
                replies.remove(userId);
            }
        }
    }
    public void clearReactions() {
        reactions.clear();
    }
    public void clearReplies() {
        replies.clear();
    }
    public void clear() {
        reactions.clear();
        replies.clear();
    }

}
