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
  public Map<String, Object> createLinkToken(@RequestParam String username) throws Exception {
    var user = new LinkTokenCreateRequestUser().clientUserId(username);

    Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();
    String redirectUri = dotenv.get("PLAID_REDIRECT_URI");

    var req = new LinkTokenCreateRequest()
        .user(user)
        .clientName("PlotLine")
        .products(List.of(Products.TRANSACTIONS))
        .countryCodes(List.of(CountryCode.US))
        .language("en");

    // iOS OAuth: include redirect_uri; Android: include android_package_name
    if (redirectUri != null && !redirectUri.isBlank()) {
      req.redirectUri(redirectUri);
    }

    var res = plaid.linkTokenCreate(req).execute().body();
    return Map.of("link_token", res.getLinkToken());
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
