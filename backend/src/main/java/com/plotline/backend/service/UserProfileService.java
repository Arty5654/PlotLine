package com.plotline.backend.service;

import java.nio.charset.StandardCharsets;

import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import com.plotline.backend.dto.UserProfile;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;


import io.github.cdimascio.dotenv.Dotenv;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.ObjectCannedACL;

@Service
public class UserProfileService {

  private final S3Client s3Client;
  private final String bucketName = "plotline-database-bucket";
  private final ObjectMapper objectMapper;
  Dotenv dotenv = Dotenv.load();

  public UserProfileService(S3Client s3Client) {
      this.s3Client = s3Client;
      this.objectMapper = new ObjectMapper();
  }

  public void saveProfile(UserProfile profile) {
      try {

          String user = objectMapper.writeValueAsString(profile);

          String username = profile.getUsername();
          String key = "users/" + username + "/profile.json";

          PutObjectRequest putRequest = PutObjectRequest.builder().
            bucket(bucketName).
            key(key).
            contentType("application/json").
            build();

            s3Client.putObject(putRequest, RequestBody.fromString(user));

      } catch (JsonProcessingException e) {
          e.printStackTrace();
      }
  }

  public UserProfile getProfile(String username) {
      
      try {

        String key = "users/" + username + "/profile.json";

        GetObjectRequest getRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build();

        ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getRequest);
        String userJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);


        UserProfile profile = objectMapper.readValue(userJson, UserProfile.class);
        return profile;

      } catch (Exception e) {
          return null;
      }
  }

  public String uploadProfilePicture(MultipartFile file, String username) throws Exception {
        String fileName = "users/" + username + "/profile_pictures/" + username + ".jpg";

        System.out.println("Uploading profile picture");

        PutObjectRequest putRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(fileName)
                .contentType(file.getContentType())
                .acl(ObjectCannedACL.PUBLIC_READ)
                .build();

        s3Client.putObject(putRequest, RequestBody.fromBytes(file.getBytes()));

        System.out.println("Profile picture uploaded successfully");

        return "https://" + bucketName + ".s3.amazonaws.com/" + fileName;
  }




  
}
