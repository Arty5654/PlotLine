package com.plotline.backend.controller;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.plotline.backend.dto.SmsRequest;
import com.plotline.backend.dto.SmsResponse;
import com.plotline.backend.dto.VerificationRequest;
import com.plotline.backend.service.SmsService;
import com.twilio.twiml.voice.Sms;

import org.springframework.web.bind.annotation.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;

@RestController
@RequestMapping("/sms")
public class SmsController {

  @Autowired
  private final SmsService smsService;
  public SmsController(SmsService smsService) {
    this.smsService = smsService;
  }

  @PostMapping("/send")
  public ResponseEntity<?> sendSms(SmsRequest smsRequest) {
    String toNumber = smsRequest.getToNumber();
    smsService.sendSms(toNumber);

    return ResponseEntity.ok().build();
  }

  @PostMapping("/send-verification")
  public ResponseEntity<SmsResponse> sendVerification(@RequestBody String rawBody) {

    try {

        ObjectMapper objectMapper = new ObjectMapper();
        JsonNode jsonNode = objectMapper.readTree(rawBody);
        

        if (!jsonNode.has("toNumber") || jsonNode.get("toNumber").asText().isEmpty()) {
            return ResponseEntity.badRequest().body(new SmsResponse(" Error: Phone number is missing", false));
        }

        String toNumber = "+1" + jsonNode.get("toNumber").asText();
        smsService.sendVerificationCode(toNumber);

        return ResponseEntity.ok(new SmsResponse("Verification code sent", true));

    } catch (Exception e) {
        return ResponseEntity.badRequest().body(new SmsResponse("Error parsing JSON", false));
    }

  }

  @PostMapping("/verify-code")
  public ResponseEntity<SmsResponse> verifyCode(VerificationRequest verificationRequest) {

    boolean isValid = smsService.verifyCode(verificationRequest.getPhoneNumber(), verificationRequest.getCode());

    if (isValid) {
      return ResponseEntity.ok(new SmsResponse("Verification successful", true));
    } else {
      return ResponseEntity.ok(new SmsResponse("Verification failed", false));
    }
  }

  
}
