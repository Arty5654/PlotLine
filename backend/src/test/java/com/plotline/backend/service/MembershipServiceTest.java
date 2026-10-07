package com.plotline.backend.service;

import com.plotline.backend.accounts.AccountDirectory;
import com.plotline.backend.testsupport.TestDatabase;
import org.springframework.jdbc.core.JdbcTemplate;
import com.apple.itunes.storekit.model.JWSTransactionDecodedPayload;
import com.apple.itunes.storekit.model.OfferDiscountType;
import com.apple.itunes.storekit.model.OfferType;
import com.plotline.backend.membership.Membership;
import com.plotline.backend.membership.MembershipService;
import com.plotline.backend.testsupport.InMemoryS3Client;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;

/** In the service package to reach AuthService's test constructor. */
class MembershipServiceTest {

    private InMemoryS3Client s3;
    private AuthService authService;
    private MembershipService membershipService;

    @BeforeEach
    void setUp() {
        s3 = new InMemoryS3Client();
        JdbcTemplate jdbc = new JdbcTemplate(TestDatabase.newDatabase());
        authService = new AuthService(s3, null, "test-jwt-secret", new AccountDirectory(jdbc));
        membershipService = new MembershipService(jdbc, authService, 2, 7);
    }

    private void signUp(String username) {
        assertThat(authService.createUser("555", username + "@mail.com", username, username, "Password1", false)).isTrue();
    }

    @Test
    @DisplayName("The first accounts (1,000 in the real app) get lifetime; later ones start with the free week")
    void earlyAccountsGetLifetime() {
        signUp("first");
        signUp("second");
        signUp("third");

        assertThat(membershipService.membership("first").getPlan()).isEqualTo(Membership.LIFETIME);
        assertThat(membershipService.hasAccess("Second")).isTrue();
        assertThat(membershipService.membership("third").getPlan()).isEqualTo(Membership.FREE_WEEK);
        assertThat(membershipService.hasAccess("third")).isTrue();
    }

    @Test
    @DisplayName("The free week counts from sign-up and locks the app when it's over")
    void freeWeekFromSignUp() {
        signUp("first");
        signUp("second");
        signUp("newbie");
        signUp("veteran");
        long eightDaysAgo = System.currentTimeMillis() - Duration.ofDays(8).toMillis();
        authService.updateUserRecord("veteran", r -> r.setCreatedAt(eightDaysAgo));

        long created = authService.getUserRecord("newbie").getCreatedAt();
        assertThat(membershipService.membership("newbie").getExpiresAt()).isEqualTo(created + Duration.ofDays(7).toMillis());
        assertThat(membershipService.hasAccess("newbie")).isTrue();

        assertThat(membershipService.membership("veteran").getPlan()).isEqualTo(Membership.FREE_WEEK);
        assertThat(membershipService.hasAccess("veteran")).isFalse();
    }

    @Test
    @DisplayName("Subscribing during or after the free week switches to the App Store's free month")
    void subscribeAfterFreeWeek() {
        signUp("first");
        signUp("second");
        signUp("subscriber");
        long monthFromNow = System.currentTimeMillis() + Duration.ofDays(30).toMillis();
        JWSTransactionDecodedPayload purchase = new JWSTransactionDecodedPayload()
                .originalTransactionId("2000").productId(MembershipService.PRODUCT_ID).expiresDate(monthFromNow)
                .offerType(OfferType.INTRODUCTORY_OFFER).offerDiscountType(OfferDiscountType.FREE_TRIAL);

        membershipService.applyPurchase("subscriber", purchase);

        Membership membership = membershipService.membership("subscriber");
        assertThat(membership.getPlan()).isEqualTo(Membership.TRIAL);
        assertThat(membership.getExpiresAt()).isEqualTo(monthFromNow);
    }

    @Test
    @DisplayName("Lifetime members who also subscribe stay lifetime")
    void lifetimeStaysLifetime() {
        signUp("early");
        JWSTransactionDecodedPayload purchase = new JWSTransactionDecodedPayload()
                .originalTransactionId("1000").productId(MembershipService.PRODUCT_ID)
                .expiresDate(System.currentTimeMillis() - 1000);

        membershipService.applyPurchase("early", purchase);

        assertThat(membershipService.membership("early").getPlan()).isEqualTo(Membership.LIFETIME);
        assertThat(membershipService.hasAccess("early")).isTrue();
    }

    @Test
    @DisplayName("Files from the old server-side trial are decided again: early accounts keep lifetime")
    void legacyStatusesDecidedAgain() {
        signUp("early");
        signUp("second");
        signUp("late");
        membershipService.write("early", Membership.of("trial")); // the old server-side trial had no expiry
        membershipService.write("late", Membership.of("grace"));

        assertThat(membershipService.membership("early").getPlan()).isEqualTo(Membership.LIFETIME);
        assertThat(membershipService.membership("late").getPlan()).isEqualTo(Membership.FREE_WEEK);
        assertThat(Membership.of("trial").isActive(System.currentTimeMillis())).isFalse();
    }
}
