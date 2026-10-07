package com.plotline.backend.membership;

import java.io.IOException;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import com.plotline.backend.security.CurrentUser;
import com.plotline.backend.security.PublicEndpoints;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * PlotLine is subscription-only: signed-in accounts without an active membership get 402
 * "Membership Required" everywhere except the paywall's own endpoints. Their data stays saved.
 * Runs right after the login filter, which identifies the user.
 */
@Component
@Order(3)
public class MembershipFilter extends OncePerRequestFilter {

    public static final String MEMBERSHIP_REQUIRED = "Membership Required";

    private final MembershipService membershipService;
    private final boolean required;

    public MembershipFilter(MembershipService membershipService,
                            @Value("${plotline.membership.required:true}") boolean required) {
        this.membershipService = membershipService;
        this.required = required;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !required || PublicEndpoints.isPublic(request) || PublicEndpoints.isAllowedWithoutMembership(request);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String user = CurrentUser.get(request);
        if (user != null && !membershipService.hasAccess(user)) {
            response.setStatus(HttpServletResponse.SC_PAYMENT_REQUIRED);
            response.setContentType("application/json");
            response.getWriter().write("{\"success\": false, \"error\": \"" + MEMBERSHIP_REQUIRED + "\"}");
            return;
        }
        chain.doFilter(request, response);
    }
}
