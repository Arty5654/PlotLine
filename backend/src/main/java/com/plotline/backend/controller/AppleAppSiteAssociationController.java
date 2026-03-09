package com.plotline.backend.controller;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AppleAppSiteAssociationController {
    private static final String TEAM_ID = "B96JRFHC45";
    private static final String BUNDLE_ID = "com.ArteomAvetissian.PlotLine";

    @GetMapping(value = "/.well-known/apple-app-site-association", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> getAppleAppSiteAssociation() {
        String aasa = """
            {
              "applinks": {
                "apps": [],
                "details": [
                  {
                    "appID": "%s.%s",
                    "paths": ["/plaid-oauth", "/plaid-oauth/*"]
                  }
                ]
              },
              "webcredentials": {
                "apps": ["%s.%s"]
              }
            }
            """.formatted(TEAM_ID, BUNDLE_ID, TEAM_ID, BUNDLE_ID);

        return ResponseEntity.ok()
            .contentType(MediaType.APPLICATION_JSON)
            .body(aasa);
    }

    // Also handle the OAuth redirect endpoint
    @GetMapping("/plaid-oauth")
    public ResponseEntity<String> plaidOAuthRedirect() {
        // This endpoint receives the OAuth redirect from Plaid
        // The iOS app should intercept this via Universal Links
        return ResponseEntity.ok("Plaid OAuth redirect received. This should open in your app.");
    }
}
