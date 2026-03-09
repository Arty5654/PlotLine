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
    Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();

    // Check System.getenv first (for Fly.io), fall back to dotenv (for local dev)
    String clientId = resolveEnv(dotenv, "PLAID_CLIENT_ID");

    String secret = resolveEnv(dotenv, "PLAID_SECRET");

    String plaidEnv = resolveEnv(dotenv, "PLAID_ENV");

    // Provide credentials via ApiClient constructor (supported in v9+ including 14.x)
    HashMap<String, String> apiKeys = new HashMap<>();
    apiKeys.put("clientId", clientId);
    apiKeys.put("secret", secret);

    ApiClient client = new ApiClient(apiKeys);

    // Choose environment based on PLAID_ENV (defaults to sandbox)
    if ("production".equalsIgnoreCase(plaidEnv)) {
      client.setPlaidAdapter(ApiClient.Production);
      System.out.println("Plaid configured for PRODUCTION environment");
    } else {
      client.setPlaidAdapter(ApiClient.Sandbox);
      System.out.println("Plaid configured for SANDBOX environment");
    }

    return client.createService(PlaidApi.class);
  }

  private static String resolveEnv(Dotenv dotenv, String key) {
    String env = System.getenv(key);
    if (env != null && !env.isBlank()) {
      return env;
    }
    return dotenv.get(key);
  }
}
