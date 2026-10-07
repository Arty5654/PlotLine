package com.plotline.backend.membership;

import com.apple.itunes.storekit.verification.VerificationException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** The real verifier: anything not signed through Apple's root certificate is refused. */
class AppStoreVerifierTest {

    private static String b64(String json) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(json.getBytes(StandardCharsets.UTF_8));
    }

    // looks like a StoreKit transaction, but the "certificates" and signature are made up
    private static final String FORGED = b64("{\"alg\":\"ES256\",\"x5c\":[\"MIIBfake\",\"MIIBfake\",\"MIIBfake\"]}")
            + "." + b64("{\"bundleId\":\"" + AppStoreVerifier.BUNDLE_ID + "\",\"productId\":\"plus_monthly\","
                    + "\"originalTransactionId\":\"1\",\"expiresDate\":4102444800000,\"environment\":\"Sandbox\"}")
            + "." + b64("not a signature");

    @Test
    @DisplayName("Forged or malformed purchases and notifications are refused")
    void refusesUnsignedData() throws Exception {
        AppStoreVerifier verifier = new AppStoreVerifier();

        assertThatThrownBy(() -> verifier.transaction(FORGED)).isInstanceOf(VerificationException.class);
        assertThatThrownBy(() -> verifier.transaction("garbage")).isInstanceOf(VerificationException.class);
        assertThatThrownBy(() -> verifier.renewalInfo(FORGED)).isInstanceOf(VerificationException.class);
        assertThatThrownBy(() -> verifier.notification(FORGED)).isInstanceOf(VerificationException.class);
    }
}
