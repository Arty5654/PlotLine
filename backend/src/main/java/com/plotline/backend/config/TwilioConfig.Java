package com.plotline.backend.config;

import com.twilio.Twilio;
import com.twilio.http.TwilioRestClient;
import io.github.cdimascio.dotenv.Dotenv;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;


@Configuration
public class TwilioConfig {

  Dotenv dotenv = Dotenv.load();
  String twilioSid = dotenv.get("TWILIO_ACCOUNT_SID");
  String twilioAuthToken = dotenv.get("TWILIO_AUTH_TOKEN");
  

  @Bean
  public TwilioRestClient twilioRestClient() {

    Twilio.init(twilioSid, twilioAuthToken);
    return Twilio.getRestClient();
  }

}
