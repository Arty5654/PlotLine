package com.plotline.backend.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import io.github.cdimascio.dotenv.Dotenv;

import java.io.IOException;

@Component
@Order(1)
public class ApiKeyFilter extends OncePerRequestFilter {

    private static final String API_KEY_HEADER = "X-API-Key";
    private final String validApiKey;

    public ApiKeyFilter() {
        Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();
        String key = System.getenv("PLOTLINE_API_KEY");
        if (key == null || key.isBlank()) {
            key = dotenv.get("PLOTLINE_API_KEY");
        }
        this.validApiKey = key;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {

        // Skip API key check if no key is configured (for local development)
        if (validApiKey == null || validApiKey.isBlank()) {
            filterChain.doFilter(request, response);
            return;
        }

        String requestApiKey = request.getHeader(API_KEY_HEADER);

        if (requestApiKey == null || !requestApiKey.equals(validApiKey)) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.setContentType("application/json");
            response.getWriter().write("{\"error\": \"Invalid or missing API key\"}");
            return;
        }

        filterChain.doFilter(request, response);
    }
}
