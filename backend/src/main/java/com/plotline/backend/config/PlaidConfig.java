package com.plotline.backend.config;

import com.plaid.client.ApiClient;
import com.plaid.client.request.PlaidApi;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import io.github.cdimascio.dotenv.Dotenv;

import java.util.HashMap;

@Configuration
public class PlaidConfig {

  @Bean
  public PlaidApi plaidApi() {
    Dotenv dotenv = Dotenv.load();
    String clientId = dotenv.get("PLAID_CLIENT_ID");
    String secret   = dotenv.get("PLAID_SECRET");

    // Provide credentials via ApiClient constructor (supported in v9+ including 14.x)
    HashMap<String, String> apiKeys = new HashMap<>();
    apiKeys.put("clientId", clientId);
    apiKeys.put("secret", secret);

    ApiClient client = new ApiClient(apiKeys);

    // Choose environment (Sandbox shown here). If this method ever changes,
    // you can replace it with client.setBasePath("https://sandbox.plaid.com");
    client.setPlaidAdapter(ApiClient.Sandbox);

    return client.createService(PlaidApi.class);
  }
}
