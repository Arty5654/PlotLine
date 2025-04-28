package com.plotline.backend.controller;

import java.io.IOException;
import java.security.Principal;
import java.util.List;
import java.util.Map;

import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.plotline.backend.dto.ChatMessage;
import com.plotline.backend.service.ChatMessageService;
import com.plotline.backend.service.FriendsService;

@RestController
@RequestMapping(path = "/chat", produces = MediaType.APPLICATION_JSON_VALUE)
public class ChatController {

    private final ChatMessageService chatService;
    private final FriendsService friendsService;

    public ChatController(ChatMessageService chatService,
                          FriendsService friendsService) {
        this.chatService = chatService;
        this.friendsService = friendsService;
    }

    // returns the feed of latest 50 messages for user and their friends
    @GetMapping("/get-feed")
    public List<ChatMessage> getFeed(@RequestParam String userId) throws Exception {

        List<String> friendIds = friendsService.getFriendList(userId).getFriends();
        return chatService.getMessagesFor(userId, friendIds);

    }

    // creates a new message
    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE)
    public ChatMessage postMessage(@RequestParam String userId,
                                   @RequestBody ChatMessage message) throws JsonProcessingException {
        return chatService.postMessage(userId, message);
    }

    // adds reaction to a post
    @PostMapping(path = "/{owner}/{messageId}/reactions",
                 consumes = MediaType.APPLICATION_JSON_VALUE)
    public ChatMessage addReaction(@PathVariable String owner,
                                   @PathVariable String messageId,
                                   @RequestBody Map<String,String> body) throws IOException {
        String emoji = body.get("emoji");
        return chatService.addReaction(owner, messageId, emoji);
    }

    //removes a reaction from post
    @DeleteMapping(path = "/{owner}/{messageId}/reactions")
    public ChatMessage removeReaction(@PathVariable String owner,
                                      @PathVariable String messageId,
                                      @RequestParam String emoji) throws IOException {
        return chatService.removeReaction(owner, messageId, emoji);
    }

    // adds reply to post
    @PostMapping(path = "/{owner}/{messageId}/replies",
    consumes = MediaType.APPLICATION_JSON_VALUE)
    public ChatMessage addReply(
      @PathVariable String owner,
      @PathVariable String messageId,
      @RequestBody Map<String,String> body) throws IOException {
      
        String userId = body.get("userId");
        String text   = body.get("text");
        if (userId == null || text == null) { 
          throw new IllegalArgumentException("Missing userId or text");
        }
      return chatService.addReply(owner, messageId, userId, text);
    }

    // removes reply from post
    @DeleteMapping(path = "/{owner}/{messageId}/replies")
    public ChatMessage removeReply(@PathVariable String owner,
                                   @PathVariable String messageId,
                                   @RequestParam String reply,
                                   Principal principal) throws IOException {
        String userId = principal.getName();
        return chatService.removeReply(owner, messageId, userId, reply);
    }
}
