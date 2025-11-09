package com.plotline.backend.costs;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.http.HttpEntity;
import org.springframework.http.MediaType;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

@Component
public class CostsWriter {

  @Value("${app.baseUrl:http://localhost:8080}")
  private String baseUrl;

  private final RestTemplate rest = new RestTemplate();

  /** Merge a single day into weekly/monthly files via your /api/costs/merge-dated endpoint. */
  public void mergeDated(String username, String type, String yyyyMmDd, Map<String, Double> costs) {
    var url = baseUrl + "/api/costs/merge-dated";
     Map<String, Object> payload = Map.of(
        "username", username,
        "type", type,
        "date", yyyyMmDd,             // "YYYY-MM-DD"
        "costs", costs
    );

    HttpHeaders headers = new HttpHeaders();
    headers.setContentType(MediaType.APPLICATION_JSON);
    headers.setAccept(java.util.List.of(MediaType.APPLICATION_JSON));

    HttpEntity<Map<String, Object>> entity = new HttpEntity<>(payload, headers);

    try {
      ResponseEntity<String> resp = rest.postForEntity(url, entity, String.class);
      if (!resp.getStatusCode().is2xxSuccessful()) {
        System.err.println("merge-dated non-200: " + resp.getStatusCode() +
            " body=" + resp.getBody());
      }
    } catch (Exception ex) {
      ex.printStackTrace();
      // Log the full response if available
      throw ex;
    }
  }
}
