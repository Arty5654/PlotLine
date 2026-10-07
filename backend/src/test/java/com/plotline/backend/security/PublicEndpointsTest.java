package com.plotline.backend.security;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;

import static org.assertj.core.api.Assertions.assertThat;

class PublicEndpointsTest {

    private static boolean isPublic(String method, String path) {
        return PublicEndpoints.isPublic(new MockHttpServletRequest(method, path));
    }

    @Test
    @DisplayName("Only sign-in, sign-up, password reset and web pages skip the login token")
    void publicList() {
        assertThat(isPublic("POST", "/auth/signin")).isTrue();
        assertThat(isPublic("POST", "/auth/signup")).isTrue();
        assertThat(isPublic("POST", "/auth/google-signin")).isTrue();
        assertThat(isPublic("POST", "/auth/apple-signin")).isTrue();
        assertThat(isPublic("POST", "/auth/change-password-code")).isTrue();
        assertThat(isPublic("POST", "/sms/send-verification")).isTrue();
        assertThat(isPublic("GET", "/invite")).isTrue();
        assertThat(isPublic("GET", "/.well-known/apple-app-site-association")).isTrue();
        assertThat(isPublic("POST", "/auth/signin/")).isTrue();
        assertThat(isPublic("POST", "/api/payments/apple/notifications")).isTrue(); // Apple's servers, signature-checked
    }

    private static boolean withoutMembership(String method, String path) {
        return PublicEndpoints.isAllowedWithoutMembership(new MockHttpServletRequest(method, path));
    }

    @Test
    @DisplayName("Without a membership, only the paywall's endpoints and account setup/deletion work")
    void withoutMembershipList() {
        assertThat(withoutMembership("GET", "/api/payments/status/alice")).isTrue();
        assertThat(withoutMembership("POST", "/api/payments/apple/sync")).isTrue();
        assertThat(withoutMembership("POST", "/auth/refresh")).isTrue();
        assertThat(withoutMembership("POST", "/auth/accept-terms")).isTrue();
        assertThat(withoutMembership("POST", "/auth/delete-account")).isTrue();
        assertThat(withoutMembership("POST", "/sms/verify-code")).isTrue();

        assertThat(withoutMembership("GET", "/api/payments/status/alice/extra")).isFalse();
        assertThat(withoutMembership("POST", "/api/payments/status/alice")).isFalse();
        assertThat(withoutMembership("GET", "/api/payments/apple/sync")).isFalse();
        assertThat(withoutMembership("GET", "/friends/get-friends")).isFalse();
        assertThat(withoutMembership("POST", "/api/llm/budget")).isFalse();
    }

    @Test
    @DisplayName("Everything else needs a token, including look-alikes and other methods")
    void everythingElseProtected() {
        assertThat(isPublic("POST", "/auth/change-password")).isFalse();
        assertThat(isPublic("POST", "/auth/delete-account")).isFalse();
        assertThat(isPublic("POST", "/auth/refresh")).isFalse();
        assertThat(isPublic("GET", "/auth/signin")).isFalse();
        assertThat(isPublic("POST", "/auth/signin-extra")).isFalse();
        assertThat(isPublic("POST", "/sms/verify-code")).isFalse();
        assertThat(isPublic("GET", "/auth/get-users")).isFalse();
        assertThat(isPublic("GET", "/api/budget/alice/monthly")).isFalse();
        assertThat(isPublic("POST", "/invite")).isFalse();
    }
}
