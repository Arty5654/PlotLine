package com.plotline.backend.controller;
import com.plotline.backend.dto.SmsRequest;
import com.plotline.backend.dto.VerificationRequest;
import com.plotline.backend.service.SmsService;
import org.springframework.web.bind.annotation.*;
import org.springframework.http.ResponseEntity;

@RestController
@RequestMapping("/sms")
public class SmsController {

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
  public ResponseEntity<String> sendVerification(SmsRequest smsRequest) {
    smsService.sendVerificationCode(smsRequest.getToNumber());
    return ResponseEntity.ok("Verification code sent to " + smsRequest.getToNumber());
  }

  @PostMapping("/verify-code")
  public ResponseEntity<String> verifyCode(VerificationRequest verificationRequest) {

    boolean isValid = smsService.verifyCode(verificationRequest.getPhoneNumber(), verificationRequest.getCode());

    if (isValid) {
      return ResponseEntity.ok("Verification successful");
    } else {
      return ResponseEntity.badRequest().body("Invalid verification code");
    }
  }

  
}
