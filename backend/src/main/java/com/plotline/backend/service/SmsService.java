package com.plotline.backend.service;

import org.springframework.stereotype.Service;

import com.twilio.http.TwilioRestClient;
import com.twilio.Twilio;
import com.twilio.type.PhoneNumber;
import com.twilio.rest.api.v2010.account.Message;
import com.twilio.rest.verify.v2.service.VerificationCheck;
import com.twilio.rest.verify.v2.service.Verification;

import io.github.cdimascio.dotenv.Dotenv;

@Service
public class SmsService {
  private final TwilioRestClient twilioRestClient;
  private final String sender;
  private final String verifyServiceSid;

  Dotenv dotenv = Dotenv.load();

  

  public SmsService() {
    String sid = dotenv.get("TWILIO_ACCOUNT_SID");
    String authToken = dotenv.get("TWILIO_AUTH_TOKEN");
    Twilio.init(sid, authToken);

    this.twilioRestClient = Twilio.getRestClient();
    this.sender = dotenv.get("TWILIO_PHONE_NUMBER");
    this.verifyServiceSid = dotenv.get("TWILIO_VERIFY_SERVICE_SID");
  }


  public void sendSms(String toNumber) {
    Message.creator(
        new PhoneNumber(toNumber),
        new PhoneNumber(sender),
        "Hello from Plotline!"
    ).create(twilioRestClient);
  }

  public void sendVerificationCode(String toNumber) {
    Verification verification = Verification.creator(
        verifyServiceSid,
        toNumber,
        "sms"
      ).create(twilioRestClient);
  }

  public boolean verifyCode(String toNumber, String code) {
    VerificationCheck verificationCheck = VerificationCheck.creator(
      verifyServiceSid
    ).setTo(toNumber).setCode(code).create(twilioRestClient);

    return "approved".equals(verificationCheck.getStatus());
  }


}
