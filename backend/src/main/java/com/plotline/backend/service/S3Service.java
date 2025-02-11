package com.plotline.backend.service;

import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import java.io.InputStream;
import java.nio.ByteBuffer;

@Service
public class S3Service {
  private final S3Client s3Client;
  private final String bucketName = "plotline-database-bucket";

  public S3Service(S3Client s3Client) {
    this.s3Client = s3Client;
  }

  public void uploadFile(String fileName, InputStream inputStream, long contentLength) {
    try {
      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(fileName)
          .build();

      s3Client.putObject(putObjectRequest, RequestBody.fromByteBuffer(ByteBuffer.wrap(inputStream.readAllBytes())));
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
