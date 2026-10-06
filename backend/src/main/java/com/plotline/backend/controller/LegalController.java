package com.plotline.backend.controller;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Public Terms of Service and Privacy Policy pages (src/main/resources/legal).
 * The app opens these, and /privacy is the privacy policy URL for App Store Connect.
 */
@RestController
public class LegalController {

    public static final String TERMS_VERSION = com.plotline.backend.util.LegalTerms.CURRENT_VERSION;

    @GetMapping(value = "/terms", produces = MediaType.TEXT_HTML_VALUE)
    public ResponseEntity<String> terms() throws IOException {
        return page("legal/terms.html");
    }

    @GetMapping(value = "/privacy", produces = MediaType.TEXT_HTML_VALUE)
    public ResponseEntity<String> privacy() throws IOException {
        return page("legal/privacy.html");
    }

    private static ResponseEntity<String> page(String path) throws IOException {
        String html = new ClassPathResource(path).getContentAsString(StandardCharsets.UTF_8);
        return ResponseEntity.ok().contentType(MediaType.TEXT_HTML).body(html);
    }
}
