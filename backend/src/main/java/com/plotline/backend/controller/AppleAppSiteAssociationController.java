package com.plotline.backend.controller;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
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
                    "paths": ["/plaid-oauth", "/plaid-oauth/*", "/invite", "/invite/*"]
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

    @GetMapping("/plaid-oauth")
    public ResponseEntity<String> plaidOAuthRedirect() {
        return ResponseEntity.ok("Plaid OAuth redirect received. This should open in your app.");
    }

    @GetMapping(value = "/invite", produces = MediaType.TEXT_HTML_VALUE)
    public ResponseEntity<String> invitePage(@RequestParam(required = false, defaultValue = "") String from) {
        String safeFrom = from.replaceAll("[^a-zA-Z0-9_\\-]", "");
        String deepLink = "plotline://add-friend?from=" + safeFrom;
        String html = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>Add %s on PlotLine</title>
                <style>
                    * { box-sizing: border-box; margin: 0; padding: 0; }
                    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #f2f2f7; display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 24px; }
                    .card { background: white; border-radius: 20px; padding: 40px 28px; text-align: center; max-width: 360px; width: 100%%; box-shadow: 0 4px 20px rgba(0,0,0,0.08); }
                    h1 { font-size: 22px; font-weight: 700; color: #1c1c1e; margin-bottom: 8px; }
                    p { color: #6c6c70; font-size: 15px; line-height: 1.5; margin-bottom: 28px; }
                    .btn { display: block; background: #007AFF; color: white; padding: 16px; border-radius: 14px; font-size: 17px; font-weight: 600; text-decoration: none; margin-bottom: 12px; }
                    .btn-secondary { background: #f2f2f7; color: #007AFF; }
                    #fallback { display: none; margin-top: 16px; font-size: 13px; color: #6c6c70; }
                </style>
            </head>
            <body>
                <div class="card">
                    <h1>Add %s on PlotLine</h1>
                    <p>%s wants to connect with you on PlotLine — a personal goal-tracking app.</p>
                    <a class="btn" href="%s" id="openBtn">Open in PlotLine</a>
                    <div id="fallback">
                        <p>Don't have PlotLine yet? Download it from the App Store to get started.</p>
                    </div>
                </div>
                <script>
                    var appLink = '%s';
                    var btn = document.getElementById('openBtn');
                    var fallback = document.getElementById('fallback');
                    btn.addEventListener('click', function(e) {
                        e.preventDefault();
                        window.location = appLink;
                        setTimeout(function() { fallback.style.display = 'block'; }, 1800);
                    });
                </script>
            </body>
            </html>
            """.formatted(safeFrom, safeFrom, safeFrom, deepLink, deepLink);

        return ResponseEntity.ok()
            .contentType(MediaType.TEXT_HTML)
            .body(html);
    }
}
