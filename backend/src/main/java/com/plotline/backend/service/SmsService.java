package com.plotline.backend.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.charset.StandardCharsets;

import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.S3UserRecord;
import com.twilio.Twilio;
import com.twilio.rest.verify.v2.service.VerificationCheck;
import com.twilio.rest.verify.v2.service.Verification;

import io.github.cdimascio.dotenv.Dotenv;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;

import static com.plotline.backend.util.UsernameUtils.normalize;

@Service
public class SmsService {
    private static final Logger log = LoggerFactory.getLogger(SmsService.class);

  // codes go out through Twilio Verify, which sends from Twilio's own numbers,
  // so no phone number of our own is needed
  private final String verifyServiceSid;
  private final S3Client s3Client;
  private final String bucketName = "plotline-database-bucket";
  private final ObjectMapper objectMapper;

  private final boolean twilioConfigured;

  private static String resolveEnv(Dotenv dotenv, String key) {
    String env = System.getenv(key);
    if (env != null && !env.isBlank()) {
      return env;
    }
    return dotenv.get(key);
  }

  public SmsService(S3Client s3Client) {
    Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();
    String sid = resolveEnv(dotenv, "TWILIO_ACCOUNT_SID");
    String authToken = resolveEnv(dotenv, "TWILIO_AUTH_TOKEN");
    this.verifyServiceSid = resolveEnv(dotenv, "TWILIO_VERIFY_SERVICE_SID");
    this.twilioConfigured = sid != null && authToken != null && verifyServiceSid != null;

    if (twilioConfigured) {
      Twilio.init(sid, authToken);
    } else {
      log.warn("Twilio credentials are not fully configured; SMS features are disabled.");
    }
    this.s3Client = s3Client;
    this.objectMapper = new ObjectMapper();
  }

  private void ensureTwilioConfigured() {
    if (!twilioConfigured) {
      throw new IllegalStateException("Twilio is not configured. Set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, and TWILIO_VERIFY_SERVICE_SID.");
    }
  }

  public void sendVerificationCode(String toNumber) {

    ensureTwilioConfigured();

    Verification verification = Verification.creator(
        verifyServiceSid,
        toNumber,
        "sms"
      ).create();

    log.debug("Verification send status: {}", verification.getStatus());
  }

  public boolean verifyCode(String toNumber, String code, String username) {
    ensureTwilioConfigured();

    if (toNumber == null || code == null || username == null) {
      log.warn("Code check missing a field (phone set: {}, code set: {}, username: {})",
          toNumber != null, code != null, username);
    }

    // verify code with twilio
    VerificationCheck verificationCheck = VerificationCheck.creator(
      verifyServiceSid
    ).setTo("+1" + toNumber)
    .setCode(code)
    .create();

    // if approved update isVerified in user account
    if ("approved".equals(verificationCheck.getStatus())) {

      try {
        String normUser = normalize(username);

        GetObjectRequest getObjectRequest = GetObjectRequest.builder()
        .bucket(bucketName)
        .key("users/" + normUser + "/account.json")
        .build();

        ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
        String userJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

        S3UserRecord userRecord = objectMapper.readValue(userJson, S3UserRecord.class);
        userRecord.setIsVerified(true);
        userRecord.setPhone(toNumber);

        String updatedUserJson = objectMapper.writeValueAsString(userRecord);

        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key("users/" + normUser + "/account.json")
          .contentType("application/json")
          .build();

        s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedUserJson));


      } catch (Exception e) {
        log.warn("Error updating user record");
      }

    }

    log.debug("Code check status: {}", verificationCheck.getStatus());
    return "approved".equals(verificationCheck.getStatus());
  }


}
