package com.plotline.backend.service;

import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;
import io.github.cdimascio.dotenv.Dotenv;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import java.io.InputStream;

@Service
public class S3Service {
  private final S3Client s3Client;
  private final String bucketName = "plotline-database-bucket";

  private final UserProfileService userProfileService;

  public S3Service(UserProfileService userProfileService) {
    Dotenv dotenv = Dotenv.load(); // Load .env file
    String accessKey = dotenv.get("AWS_ACCESS_KEY_ID");
    String secretKey = dotenv.get("AWS_SECRET_ACCESS_KEY");
    String region = dotenv.get("AWS_REGION");
    String jwtKey = dotenv.get("JWT_SECRET_KEY");
    this.userProfileService = userProfileService;

    this.s3Client = S3Client.builder()
        .region(Region.of(region))
        .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(accessKey, secretKey)))
        .build();
  }

  public void uploadFile(String fileName, InputStream inputStream, long contentLength) {
    try {
      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(fileName)
          .contentLength(contentLength)
          .build();

      s3Client.putObject(putObjectRequest, RequestBody.fromInputStream(inputStream, contentLength));
    } catch (Exception e) {
      throw new RuntimeException("Error uploading file to S3", e);
    }
  }

  public byte[] downloadFile(String fileName) {
    try {
      GetObjectRequest getObjectRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(fileName)
          .build();

      ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
      return objectBytes.asByteArray();
    } catch (Exception e) {
      throw new RuntimeException("Error downloading file from S3", e);
    }
  }

  public void deleteFile(String fileName) {
    try {
      DeleteObjectRequest deleteObjectRequest = DeleteObjectRequest.builder()
          .bucket(bucketName)
          .key(fileName)
          .build();

      s3Client.deleteObject(deleteObjectRequest);
    } catch (Exception e) {
      throw new RuntimeException("Error deleting file from S3", e);
    }
  }

}
