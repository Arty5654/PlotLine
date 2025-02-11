package com.plotline.backend.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.EnvironmentVariableCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;

@Configuration
public class AWSConfig {

  @Bean
  public S3Client s3Client() {
    return S3Client.builder()
        .region(Region.US_EAST_2)
        .credentialsProvider(EnvironmentVariableCredentialsProvider.create())
        .build();
  }
}
