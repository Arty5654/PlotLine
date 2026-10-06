package com.plotline.backend.security;

import java.io.IOException;

import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import com.plotline.backend.service.AuthService;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * Requires a valid login token (Authorization: Bearer ...) on every non-public endpoint and
 * records who the caller is. Runs after the API key check.
 */
@Component
@Order(2)
public class JwtAuthFilter extends OncePerRequestFilter {

    private final AuthService authService;

    public JwtAuthFilter(AuthService authService) {
        this.authService = authService;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return PublicEndpoints.isPublic(request);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        String token = header != null && header.startsWith("Bearer ") ? header.substring(7).trim() : null;
        String username = authService.authenticatedUsername(token);

        if (username == null) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.setContentType("application/json");
            response.getWriter().write("{\"success\": false, \"error\": \"Please sign in again.\"}");
            return;
        }

        // accounts that haven't accepted the terms or verified their phone can only finish that step
        String pendingStep = authService.pendingAccountStep(username);
        if (pendingStep != null && !PublicEndpoints.isAllowedDuringSetup(request)) {
            response.setStatus(HttpServletResponse.SC_FORBIDDEN);
            response.setContentType("application/json");
            response.getWriter().write("{\"success\": false, \"error\": \"" + pendingStep + "\"}");
            return;
        }

        request.setAttribute(CurrentUser.ATTRIBUTE, username);
        filterChain.doFilter(request, response);
    }
}
