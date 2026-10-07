package com.plotline.backend.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.FriendList;
import com.plotline.backend.dto.FriendPost;
import com.plotline.backend.dto.LongTermGoal;
import static com.plotline.backend.util.UsernameUtils.normalize;

import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;

import java.sql.Array;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.UUID;

/**
 * The friends feed: goals people share, with likes and comments. Posts live in Postgres
 * (feed_posts), one row each, so likes and comments are single updates that can't erase each
 * other, and a feed only reads its friends' posts. Friend lists are still in S3.
 */
@Service
public class FriendsFeedService {
    private static final Logger log = LoggerFactory.getLogger(FriendsFeedService.class);

  private final S3Client s3Client;
  private final JdbcTemplate jdbc;
  private final String bucketName = "plotline-database-bucket";
  private final ObjectMapper objectMapper = new ObjectMapper();

  public FriendsFeedService(S3Client s3Client, JdbcTemplate jdbc) {
    this.s3Client = s3Client; // shared client from AWSConfig
    this.jdbc = jdbc;
  }

  public boolean addPostToFeed(FriendPost post) {
    try {
      insert(post);
      return true;
    } catch (DuplicateKeyException e) {
      return false;
    } catch (Exception e) {
      log.error("addPostToFeed failed", e);
      return false;
    }
  }

  /** also used to copy the old feed file into the database (S3DataImport) */
  public void insert(FriendPost post) throws Exception {
    UUID id = post.getId() != null ? post.getId() : UUID.randomUUID();
    String goal = post.getGoal() != null ? objectMapper.writeValueAsString(post.getGoal()) : null;
    String comments = objectMapper.writeValueAsString(post.getComments() != null ? post.getComments() : List.of());
    String[] likedBy = post.getLikedBy() != null ? post.getLikedBy().toArray(new String[0]) : new String[0];
    jdbc.update(con -> {
      var statement = con.prepareStatement("""
          insert into feed_posts (id, username, author, goal, comment, liked_by, comments)
          values (?, ?, ?, ?::jsonb, ?, ?, ?::jsonb)
          """);
      statement.setObject(1, id);
      statement.setString(2, post.getUsername());
      statement.setString(3, normalize(post.getUsername()));
      statement.setString(4, goal);
      statement.setString(5, post.getComment());
      statement.setArray(6, con.createArrayOf("text", likedBy));
      statement.setString(7, comments);
      return statement;
    });
  }

  /** posts by the user and their friends, oldest first */
  public List<FriendPost> getFriendsFeed(String username) {
    try {
      List<String> authors = new ArrayList<>();
      for (String friend : friendsOf(username)) authors.add(normalize(friend));
      authors.add(normalize(username)); // always see your own posts

      return jdbc.query(con -> {
        var statement = con.prepareStatement(
            "select id, username, goal, comment, liked_by, comments from feed_posts where author = any(?) order by seq");
        statement.setArray(1, con.createArrayOf("text", authors.toArray()));
        return statement;
      }, postMapper);
    } catch (Exception e) {
      log.error("getFriendsFeed failed", e);
      return new ArrayList<>();
    }
  }

  private List<String> friendsOf(String username) throws Exception {
    try {
      GetObjectRequest friendsRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key("users/" + normalize(username) + "/friends.json")
          .build();
      ResponseBytes<?> friendsBytes = s3Client.getObjectAsBytes(friendsRequest);
      List<String> friends = objectMapper.readValue(friendsBytes.asByteArray(), FriendList.class).getFriends();
      return friends != null ? friends : List.of();
    } catch (NoSuchKeyException e) {
      return List.of(); // no friends list file yet
    }
  }

  private final RowMapper<FriendPost> postMapper = (row, i) -> {
    try {
      FriendPost post = new FriendPost();
      post.setId(row.getObject("id", UUID.class));
      post.setUsername(row.getString("username"));
      String goal = row.getString("goal");
      post.setGoal(goal != null ? objectMapper.readValue(goal, LongTermGoal.class) : null);
      post.setComment(row.getString("comment"));
      Array likedBy = row.getArray("liked_by");
      post.setLikedBy(new LinkedHashSet<>(Arrays.asList((String[]) likedBy.getArray())));
      post.setComments(objectMapper.readValue(row.getString("comments"), new TypeReference<List<String>>() { }));
      return post;
    } catch (Exception e) {
      throw new IllegalStateException("Couldn't read feed post", e);
    }
  };

  /** only your own posts can be deleted */
  public boolean deletePostById(String username, UUID postId) {
    try {
      jdbc.update("delete from feed_posts where id = ? and author = ?", postId, normalize(username));
      return true;
    } catch (Exception e) {
      log.error("deletePostById failed", e);
      return false;
    }
  }

  public boolean toggleLike(String username, UUID postId) {
    try {
      jdbc.update("""
          update feed_posts set liked_by = case
              when ? = any(liked_by) then array_remove(liked_by, ?)
              else array_append(liked_by, ?) end
          where id = ?
          """, username, username, username, postId);
      return true;
    } catch (Exception e) {
      log.error("toggleLike failed", e);
      return false;
    }
  }

  public boolean addComment(String username, UUID postId, String comment) {
    try {
      jdbc.update("update feed_posts set comments = comments || jsonb_build_array(?::text) where id = ?",
          username + ": " + comment, postId);
      return true;
    } catch (Exception e) {
      log.error("addComment failed", e);
      return false;
    }
  }

  // account deletion: drop the user's posts, likes and comments from the feed
  public void removeUser(String username) {
    String user = normalize(username);
    jdbc.update("delete from feed_posts where author = ?", user);
    jdbc.update("""
        update feed_posts set liked_by = array(select liker from unnest(liked_by) liker where lower(liker) <> ?)
        where exists (select 1 from unnest(liked_by) liker where lower(liker) = ?)
        """, user, user);
    jdbc.update("""
        update feed_posts set comments = coalesce(
            (select jsonb_agg(c) from jsonb_array_elements(comments) c where not starts_with(lower(c #>> '{}'), ?)),
            '[]'::jsonb)
        where exists (select 1 from jsonb_array_elements(comments) c where starts_with(lower(c #>> '{}'), ?))
        """, user + ": ", user + ": ");
  }
}
