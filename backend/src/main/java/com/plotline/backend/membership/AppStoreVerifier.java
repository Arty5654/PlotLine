package com.plotline.backend.membership;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import com.apple.itunes.storekit.model.Environment;
import com.apple.itunes.storekit.model.JWSRenewalInfoDecodedPayload;
import com.apple.itunes.storekit.model.JWSTransactionDecodedPayload;
import com.apple.itunes.storekit.model.ResponseBodyV2DecodedPayload;
import com.apple.itunes.storekit.verification.SignedDataVerifier;
import com.apple.itunes.storekit.verification.VerificationException;
import com.apple.itunes.storekit.verification.VerificationStatus;

import io.github.cdimascio.dotenv.Dotenv;

/**
 * Checks that purchase data really comes from the App Store for this app: Apple's signature
 * (chained to Apple Root CA G3, bundled in resources/apple), our bundle ID, and the environment.
 *
 * Accepts Production (needs APPLE_APP_APPLE_ID, the app's numeric Apple ID from App Store
 * Connect) and Sandbox (TestFlight, App Review and sandbox testers). Purchases made with a local
 * .storekit file aren't signed by Apple, so they're only accepted when
 * APPLE_ALLOW_XCODE_PURCHASES=true, which must never be set on the real server.
 */
@Component
public class AppStoreVerifier {
    private static final Logger log = LoggerFactory.getLogger(AppStoreVerifier.class);


    public static final String BUNDLE_ID = "com.ArteomAvetissian.PlotLine";

    private final List<SignedDataVerifier> verifiers = new ArrayList<>();

    public AppStoreVerifier() throws Exception {
        Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();
        byte[] rootCertificate = new ClassPathResource("apple/AppleRootCA-G3.cer").getContentAsByteArray();

        String appAppleId = dotenv.get("APPLE_APP_APPLE_ID");
        if (appAppleId != null && !appAppleId.isBlank()) {
            verifiers.add(verifier(rootCertificate, Long.parseLong(appAppleId.trim()), Environment.PRODUCTION));
        } else {
            log.warn("WARNING: APPLE_APP_APPLE_ID not set; App Store (production) purchases can't be verified");
        }
        verifiers.add(verifier(rootCertificate, null, Environment.SANDBOX));
        if ("true".equalsIgnoreCase(dotenv.get("APPLE_ALLOW_XCODE_PURCHASES"))) {
            log.warn("WARNING: accepting unsigned Xcode test purchases (APPLE_ALLOW_XCODE_PURCHASES)");
            verifiers.add(verifier(rootCertificate, null, Environment.XCODE));
        }
    }

    private static SignedDataVerifier verifier(byte[] rootCertificate, Long appAppleId, Environment environment) {
        Set<InputStream> roots = Set.of(new ByteArrayInputStream(rootCertificate));
        return new SignedDataVerifier(roots, BUNDLE_ID, appAppleId, environment, true);
    }

    @FunctionalInterface
    private interface Check<T> {
        T verify(SignedDataVerifier verifier) throws VerificationException;
    }

    // each verifier only accepts its own environment, so try them in turn
    private <T> T firstAccepted(Check<T> check) throws VerificationException {
        VerificationException last = new VerificationException(VerificationStatus.INVALID_ENVIRONMENT);
        for (SignedDataVerifier verifier : verifiers) {
            try {
                return check.verify(verifier);
            } catch (VerificationException e) {
                if (e.getStatus() != VerificationStatus.INVALID_ENVIRONMENT) throw e;
                last = e;
            }
        }
        throw last;
    }

    /** a transaction the app got from StoreKit (Transaction.jwsRepresentation) */
    public JWSTransactionDecodedPayload transaction(String signedTransaction) throws VerificationException {
        return firstAccepted(v -> v.verifyAndDecodeTransaction(signedTransaction));
    }

    public JWSRenewalInfoDecodedPayload renewalInfo(String signedRenewalInfo) throws VerificationException {
        return firstAccepted(v -> v.verifyAndDecodeRenewalInfo(signedRenewalInfo));
    }

    /** an App Store Server Notification (v2) body's signedPayload */
    public ResponseBodyV2DecodedPayload notification(String signedPayload) throws VerificationException {
        return firstAccepted(v -> v.verifyAndDecodeNotification(signedPayload));
    }
}
