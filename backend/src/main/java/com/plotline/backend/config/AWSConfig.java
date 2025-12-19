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

  private final Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load(); // don't crash if .env is absent

  private String resolve(String key) {
    String envVal = System.getenv(key);
    if (envVal != null && !envVal.isBlank()) return envVal;
    String dotVal = dotenv.get(key);
    if (dotVal != null && !dotVal.isBlank()) return dotVal;
    return null;
  }

  @Bean
  public S3Client s3Client() {
    String accessKey = resolve("AWS_ACCESS_KEY_ID");
    String secretKey = resolve("AWS_SECRET_ACCESS_KEY");
    String region = resolve("AWS_REGION");
    Region awsRegion = region != null ? Region.of(region) : Region.US_EAST_1;

    return S3Client.builder()
        .region(awsRegion)
        .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(accessKey, secretKey)))
        .build();
  }
}
