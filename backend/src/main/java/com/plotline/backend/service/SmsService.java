package com.plotline.backend.service;

import java.nio.charset.StandardCharsets;

import org.springframework.stereotype.Service;

import com.twilio.http.TwilioRestClient;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.plotline.backend.dto.S3UserRecord;
import com.twilio.Twilio;
import com.twilio.type.PhoneNumber;
import com.twilio.rest.api.v2010.account.Message;
import com.twilio.rest.verify.v2.service.VerificationCheck;
import com.twilio.rest.verify.v2.service.Verification;

import io.github.cdimascio.dotenv.Dotenv;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;

@Service
public class SmsService {
  private final TwilioRestClient twilioRestClient;
  private final String sender;
  private final String verifyServiceSid;
  private final S3Client s3Client;
  private final String bucketName = "plotline-database-bucket";
  private final ObjectMapper objectMapper;

  Dotenv dotenv = Dotenv.load();

  

  public SmsService(S3Client s3Client) {
    String sid = dotenv.get("TWILIO_ACCOUNT_SID");
    String authToken = dotenv.get("TWILIO_AUTH_TOKEN");
    Twilio.init(sid, authToken);

    this.twilioRestClient = Twilio.getRestClient();
    this.sender = dotenv.get("TWILIO_PHONE_NUMBER");
    this.verifyServiceSid = dotenv.get("TWILIO_VERIFY_SERVICE_SID");
    this.s3Client = s3Client;
    this.objectMapper = new ObjectMapper();
  }


  public void sendSms(String toNumber) {
    Message.creator(
        new PhoneNumber(toNumber),
        new PhoneNumber(sender),
        "Hello from Plotline!"
    ).create(twilioRestClient);
  }

  public void sendVerificationCode(String toNumber) {

    String sid = dotenv.get("TWILIO_ACCOUNT_SID");
    String authToken = dotenv.get("TWILIO_AUTH_TOKEN");
    Twilio.init(sid, authToken);

    Verification verification = Verification.creator(
        verifyServiceSid,
        toNumber,
        "sms"
      ).create();

    System.out.println("Verification send status: " + verification.getStatus());
  }

  public boolean verifyCode(String toNumber, String code, String username) {

    if (toNumber == null || code == null || username == null) {
      System.out.println("To " + toNumber + ", Code " + code + ", Username " + username);
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

        GetObjectRequest getObjectRequest = GetObjectRequest.builder()
        .bucket(bucketName)
        .key("users/" + username + "/account.json")
        .build();

        ResponseBytes<GetObjectResponse> objectBytes = s3Client.getObjectAsBytes(getObjectRequest);
        String userJson = new String(objectBytes.asByteArray(), StandardCharsets.UTF_8);

        S3UserRecord userRecord = objectMapper.readValue(userJson, S3UserRecord.class);
        userRecord.setIsVerified(true);
        userRecord.setPhone(toNumber);

        String updatedUserJson = objectMapper.writeValueAsString(userRecord);

        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key("users/" + username + "/account.json")
          .contentType("application/json")
          .build();

        s3Client.putObject(putObjectRequest, RequestBody.fromString(updatedUserJson));


      } catch (Exception e) {
        System.out.println("Error updating user record");
      }

    }

    System.out.println("Code check status: " + verificationCheck.getStatus());
    return "approved".equals(verificationCheck.getStatus());
  }


}
