package com.plotline.backend.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import io.github.cdimascio.dotenv.Dotenv;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;

@Configuration
public class AWSConfig {

  Dotenv dotenv = Dotenv.load(); // Load .env file
  String accessKey = dotenv.get("AWS_ACCESS_KEY_ID");
  String secretKey = dotenv.get("AWS_SECRET_ACCESS_KEY");
  String region = dotenv.get("AWS_REGION");

  @Bean
  public S3Client s3Client() {
    return S3Client.builder()
        .region(Region.US_EAST_2)
        .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(accessKey, secretKey)))
        .build();
  }
}
