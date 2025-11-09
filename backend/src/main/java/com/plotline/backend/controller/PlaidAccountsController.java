package com.plotline.backend.controller;

import com.plaid.client.model.*;
import com.plaid.client.request.PlaidApi;
import com.plotline.backend.plaid.TokenStore;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@CrossOrigin(origins = "*") // helpful if you try on-device
@RestController
@RequestMapping("/api/plaid")
public class PlaidAccountsController {
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
      System.out.println("No items for " + username);
      return List.of();
    }
    System.out.println("items: " + items);
    System.out.println("username: " + username);

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
    System.out.println("accounts returned: " + out.size());
    return out;
  }
}
