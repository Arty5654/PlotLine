package com.plotline.backend.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import com.apple.itunes.storekit.model.JWSRenewalInfoDecodedPayload;
import com.apple.itunes.storekit.model.JWSTransactionDecodedPayload;
import com.apple.itunes.storekit.model.ResponseBodyV2DecodedPayload;
import com.apple.itunes.storekit.verification.VerificationException;
import com.plotline.backend.membership.AppStoreVerifier;
import com.plotline.backend.membership.Membership;
import com.plotline.backend.membership.MembershipService;
import com.plotline.backend.membership.MembershipService.SyncResult;
import com.plotline.backend.security.CurrentUser;

/**
 * Membership: the first 1,000 accounts are free forever; everyone else subscribes through the
 * App Store (one free trial per Apple ID, then monthly). The app sends each purchase here, and
 * Apple's server notifications keep renewals, cancellations and refunds up to date.
 */
@RestController
@RequestMapping("/api/payments")
public class PaymentController {
    private static final Logger log = LoggerFactory.getLogger(PaymentController.class);


    private final MembershipService membershipService;
    private final AppStoreVerifier appStoreVerifier;

    public PaymentController(MembershipService membershipService, AppStoreVerifier appStoreVerifier) {
        this.membershipService = membershipService;
        this.appStoreVerifier = appStoreVerifier;
    }

    @GetMapping("/status/{username}")
    public ResponseEntity<?> status(@PathVariable String username) {
        return ResponseEntity.ok(view(membershipService.membership(username)));
    }

    /** a purchase or restore from the app: {"signedTransaction": Transaction.jwsRepresentation} */
    @PostMapping("/apple/sync")
    public ResponseEntity<?> syncApplePurchase(@RequestBody Map<String, String> body) {
        String signedTransaction = body.get("signedTransaction");
        if (signedTransaction == null || signedTransaction.isBlank()) {
            return error(HttpStatus.BAD_REQUEST, "signedTransaction required");
        }
        JWSTransactionDecodedPayload transaction;
        try {
            transaction = appStoreVerifier.transaction(signedTransaction);
        } catch (VerificationException e) {
            log.error("App Store purchase failed verification: {}", e.getStatus());
            return error(HttpStatus.BAD_REQUEST, "We couldn't verify this purchase with the App Store.");
        }

        SyncResult result = membershipService.applyPurchase(CurrentUser.require(), transaction);
        if (result.error() != null) {
            HttpStatus status = MembershipService.ALREADY_LINKED.equals(result.error()) ? HttpStatus.CONFLICT : HttpStatus.BAD_REQUEST;
            return error(status, result.error());
        }
        return ResponseEntity.ok(view(result.membership()));
    }

    /** App Store Server Notifications v2 (set this URL in App Store Connect): {"signedPayload": ...} */
    @PostMapping("/apple/notifications")
    public ResponseEntity<?> appleNotification(@RequestBody Map<String, String> body) {
        String signedPayload = body.get("signedPayload");
        if (signedPayload == null || signedPayload.isBlank()) {
            return error(HttpStatus.BAD_REQUEST, "signedPayload required");
        }
        try {
            ResponseBodyV2DecodedPayload notification = appStoreVerifier.notification(signedPayload);
            if (notification.getData() == null || notification.getData().getSignedTransactionInfo() == null) {
                return ResponseEntity.ok().build(); // e.g. TEST notifications
            }
            JWSTransactionDecodedPayload transaction =
                    appStoreVerifier.transaction(notification.getData().getSignedTransactionInfo());
            String signedRenewal = notification.getData().getSignedRenewalInfo();
            JWSRenewalInfoDecodedPayload renewal = signedRenewal != null ? appStoreVerifier.renewalInfo(signedRenewal) : null;
            membershipService.applyNotification(transaction, renewal);
            return ResponseEntity.ok().build();
        } catch (VerificationException e) {
            log.error("App Store notification failed verification: {}", e.getStatus());
            return error(HttpStatus.BAD_REQUEST, "Invalid notification");
        }
    }

    // what the app sees: plan, whether it's unlocked, and until when
    private static Map<String, Object> view(Membership membership) {
        Map<String, Object> view = new LinkedHashMap<>();
        view.put("plan", membership.getPlan());
        view.put("active", membership.isActive(System.currentTimeMillis()));
        view.put("expiresAt", membership.getExpiresAt() != null ? Instant.ofEpochMilli(membership.getExpiresAt()).toString() : null);
        view.put("autoRenews", membership.getAutoRenews());
        view.put("revoked", membership.isRevoked());
        return view;
    }

    private static ResponseEntity<?> error(HttpStatus status, String message) {
        return ResponseEntity.status(status).body(Map.of("success", false, "error", message));
    }
}
