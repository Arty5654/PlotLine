package com.plotline.backend.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.plaid.client.model.*;
import com.plaid.client.request.PlaidApi;
import com.plotline.backend.plaid.TokenStore;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@CrossOrigin(origins = "*") // helpful if you try on-device
@RestController
@RequestMapping("/api/plaid")
public class PlaidAccountsController {
    private static final Logger log = LoggerFactory.getLogger(PlaidAccountsController.class);

  private final PlaidApi plaid;
  private final TokenStore tokenStore;

  public PlaidAccountsController(PlaidApi plaid, TokenStore tokenStore) {
    this.plaid = plaid;
    this.tokenStore = tokenStore;
  }

  public static record AccountOut(
      String id, String name, String mask, String type, String subtype, String itemId
  ) {}

  @GetMapping("/accounts")
  public List<AccountOut> list(@RequestParam String username) throws Exception {
    Map<String,String> items = tokenStore.listAccessTokens(username);
    if (items.isEmpty()) {
      log.debug("No items for {}", username);
      return List.of();
    }
    log.debug("items: {}", items);
    log.debug("username: {}", username);

    List<AccountOut> out = new ArrayList<>();

    for (var e : items.entrySet()) {
      String itemId = e.getKey();
      String token  = e.getValue();

      AccountsGetResponse accs = plaid.accountsGet(
          new AccountsGetRequest().accessToken(token)
      ).execute().body();

      if (accs == null || accs.getAccounts() == null) continue;

      for (AccountBase a : accs.getAccounts()) {
        String type    = a.getType()    != null ? a.getType().getValue()    : null;
        String subtype = a.getSubtype() != null ? a.getSubtype().getValue() : null;

        out.add(new AccountOut(
            a.getAccountId(),
            a.getName(),
            a.getMask(),
            type,
            subtype,
            itemId
        ));
      }
    }
    log.debug("accounts returned: {}", out.size());
    return out;
  }
}
