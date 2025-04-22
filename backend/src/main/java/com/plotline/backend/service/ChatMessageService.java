package com.plotline.backend.service;

import java.nio.charset.StandardCharsets;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.locks.ReentrantLock;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import org.springframework.stereotype.Service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.ChatMessage;

import java.io.IOException;                      // <-- correct IOException
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Object;

@Service
public class ChatMessageService {

    private static final DateTimeFormatter FORMATTER =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssXXX");

    private final S3Client      s3Client;
    private final ObjectMapper  objectMapper;
    private final String        bucketName = "plotline-database-bucket";
    private final UserProfileService userProfileService;

    private final ReentrantLock reactionLock = new ReentrantLock();

    public ChatMessageService(S3Client s3Client,
                              UserProfileService userProfileService) {
        this.s3Client           = s3Client;
        this.objectMapper       = new ObjectMapper();
        this.userProfileService = userProfileService;
    }

    public ChatMessage postMessage(String username,
                                   ChatMessage message) throws JsonProcessingException {

        // 1) assign ID + timestamp
        message.setId(UUID.randomUUID().toString());
        message.setTimestamp(
            ZonedDateTime.now(ZoneOffset.UTC).format(FORMATTER)
        );

        // 2) serialize
        byte[] payload = objectMapper.writeValueAsBytes(message);

        // 3) build & execute upload
        String key = String.format("chat-messages/%s/%s.json",
                                   username, message.getId());
        PutObjectRequest putReq = PutObjectRequest.builder()
            .bucket(bucketName)
            .key(key)
            .contentType("application/json")
            .build();

        s3Client.putObject(putReq, RequestBody.fromBytes(payload));
        return message;
    }

    public List<ChatMessage> getMessagesFor(String userId,
                                            List<String> friendIds) throws IOException {
        List<ChatMessage> all = new ArrayList<>();

        // combine your own + friends
        List<String> prefixes = Stream.concat(
            friendIds.stream(),
            Stream.of(userId)
        ).toList();

        for (String uid : prefixes) {
            String prefix = "chat-messages/" + uid + "/";

            // list objects
            ListObjectsV2Request listReq = ListObjectsV2Request.builder()
                .bucket(bucketName)
                .prefix(prefix)
                .build();
            ListObjectsV2Response listRes = s3Client.listObjectsV2(listReq);

            // download & deserialize each
            for (S3Object obj : listRes.contents()) {
                GetObjectRequest getReq = GetObjectRequest.builder()
                    .bucket(bucketName)
                    .key(obj.key())
                    .build();

                ResponseBytes<GetObjectResponse> resp =
                    s3Client.getObjectAsBytes(getReq);

                ChatMessage dto = objectMapper
                    .readValue(resp.asByteArray(), ChatMessage.class);
                all.add(dto);
            }
        }

        // sort by ISO‑8601 timestamp desc and cap at 50
        return all.stream()
                  .sorted(Comparator.comparing(ChatMessage::getTimestamp).reversed())
                  .limit(50)
                  .collect(Collectors.toList());
    }

    private ChatMessage fetchRaw(String owner, String messageId) throws IOException {
      String key = String.format("chat-messages/%s/%s.json", owner, messageId);
      GetObjectRequest getReq = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

      ResponseBytes<GetObjectResponse> resp = s3Client.getObjectAsBytes(getReq);
      return objectMapper.readValue(resp.asByteArray(), ChatMessage.class);
  }

  // helper to serialize & save
  private ChatMessage saveRaw(String owner, ChatMessage msg) throws JsonProcessingException {
      String key = String.format("chat-messages/%s/%s.json", owner, msg.getId());
      byte[] json = objectMapper.writeValueAsBytes(msg);

      PutObjectRequest putReq = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .contentType("application/json")
          .build();

      s3Client.putObject(putReq, RequestBody.fromBytes(json));
      return msg;
  }

  public ChatMessage addReaction(String owner,
                                String messageId,
                                String emoji) throws IOException {
    reactionLock.lock();
    try {

      ChatMessage msg = fetchRaw(owner, messageId);
      msg.addReaction(emoji);
      return saveRaw(owner, msg);

    } finally {
      reactionLock.unlock();
    }
  }

  public ChatMessage removeReaction(String owner,
                                    String messageId,
                                    String emoji) throws IOException {

    reactionLock.lock();
    try {
      ChatMessage msg = fetchRaw(owner, messageId);
      msg.removeReaction(emoji);
      return saveRaw(owner, msg);
    } finally {
      reactionLock.unlock();
    }

  }
  public ChatMessage removeReply(String owner,
                                String messageId,
                                String userId,
                                String replyId) throws IOException {
                                  
    ChatMessage msg = fetchRaw(owner, messageId);
    msg.removeReply(userId, replyId);
    return saveRaw(owner, msg);
  }

    public ChatMessage addReply(String owner,
                                String messageId,
                                String userId,
                                String text) throws IOException {
        ChatMessage msg = fetchRaw(owner, messageId);
        msg.addReply(userId, text);
        return saveRaw(owner, msg);
    }

}
