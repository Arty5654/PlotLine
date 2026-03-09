package com.plotline.backend.controller;

import com.plaid.client.request.PlaidApi;
import com.plaid.client.model.*;
import com.plotline.backend.plaid.TokenStore;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import io.github.cdimascio.dotenv.Dotenv;

import java.util.List;
import java.util.Map;

  @RestController
  @RequestMapping("/api/plaid")
  public class PlaidController {
    private final PlaidApi plaid;
    private final TokenStore tokenStore;

    public PlaidController(PlaidApi plaid, TokenStore tokenStore) {
      this.plaid = plaid;
      this.tokenStore = tokenStore;
    }

  @GetMapping("/link_token")
  public ResponseEntity<?> createLinkToken(@RequestParam String username) {
    try {
      var user = new LinkTokenCreateRequestUser().clientUserId(username);

      String redirectUri = System.getenv("PLAID_REDIRECT_URI");
      if (redirectUri == null || redirectUri.isBlank()) {
        Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();
        redirectUri = dotenv.get("PLAID_REDIRECT_URI");
      }

      System.out.println("Creating link token for user: " + username);
      System.out.println("Redirect URI: " + redirectUri);

      var req = new LinkTokenCreateRequest()
          .user(user)
          .clientName("PlotLine")
          .products(List.of(Products.TRANSACTIONS))
          .countryCodes(List.of(CountryCode.US))
          .language("en");

      // iOS OAuth: include redirect_uri
      if (redirectUri != null && !redirectUri.isBlank()) {
        req.redirectUri(redirectUri);
      }

      var response = plaid.linkTokenCreate(req).execute();

      if (!response.isSuccessful()) {
        String errorBody = response.errorBody() != null ? response.errorBody().string() : "No error body";
        System.err.println("Plaid error: " + response.code() + " - " + errorBody);
        return ResponseEntity.status(response.code())
            .body(Map.of("error", "Plaid API error", "details", errorBody));
      }

      var body = response.body();
      return ResponseEntity.ok(Map.of("link_token", body.getLinkToken()));
    } catch (Exception e) {
      System.err.println("Exception creating link token: " + e.getMessage());
      e.printStackTrace();
      return ResponseEntity.status(500)
          .body(Map.of("error", "Failed to create link token", "message", e.getMessage()));
    }
  }


  public record ExchangeBody(String username, String public_token, List<String> account_ids) {}

  @PostMapping("/exchange")
  public ResponseEntity<?> exchange(@RequestBody ExchangeBody body) throws Exception {
    var exchangeReq = new ItemPublicTokenExchangeRequest().publicToken(body.public_token());
    var exchangeRes = plaid.itemPublicTokenExchange(exchangeReq).execute().body();

    var accessToken = exchangeRes.getAccessToken();
    var itemId      = exchangeRes.getItemId();

    tokenStore.saveAccessToken(body.username(), itemId, accessToken);

    List<String> selected = body.account_ids();
    if (selected == null || selected.isEmpty()) {
      // Fallback: pick the card automatically (e.g., PFB Credit Card / credit card type)
      AccountsGetResponse accs = plaid.accountsGet(
          new AccountsGetRequest().accessToken(accessToken)
      ).execute().body();

      selected = accs.getAccounts().stream()
          //.filter(a -> "credit".equalsIgnoreCase(a.getType()))
          //.filter(a -> a.getSubtype() != null && a.getSubtype().toLowerCase().contains("credit"))
          .filter(a -> a.getType() == AccountType.CREDIT)
          // prioritize "PFB Credit Card" name if present
          .sorted((a, b) -> {
            boolean an = a.getName() != null && a.getName().toLowerCase().contains("pfb");
            boolean bn = b.getName() != null && b.getName().toLowerCase().contains("pfb");
            return Boolean.compare(bn, an); // put PFB-like first
          })
          .map(AccountBase::getAccountId)
          .findFirst()
          .map(List::of)
          .orElseGet(List::of);
    }

    if (selected != null && !selected.isEmpty()) {
      tokenStore.saveSelectedAccounts(body.username(), itemId, selected);
    }

    return ResponseEntity.ok(Map.of("ok", true, "item_id", itemId, "selected_accounts", selected));
  }

  @PostMapping("/select_accounts")
  public ResponseEntity<?> setSelected(@RequestParam String username,
                                      @RequestParam String itemId,
                                      @RequestBody List<String> accountIds) {
    tokenStore.saveSelectedAccounts(username, itemId, accountIds);
    return ResponseEntity.ok(Map.of("ok", true));
  }

}
