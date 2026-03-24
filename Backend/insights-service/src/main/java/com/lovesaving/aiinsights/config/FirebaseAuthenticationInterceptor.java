package com.lovesaving.aiinsights.config;

import com.google.firebase.auth.FirebaseAuthException;
import com.lovesaving.aiinsights.model.AuthenticatedUser;
import com.lovesaving.aiinsights.service.FirebaseTokenVerifier;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.servlet.HandlerInterceptor;

@Component
public class FirebaseAuthenticationInterceptor implements HandlerInterceptor {

    public static final String AUTHENTICATED_USER_REQUEST_ATTRIBUTE = "authenticatedUser";
    private final FirebaseTokenVerifier tokenVerifier;

    public FirebaseAuthenticationInterceptor(FirebaseTokenVerifier tokenVerifier) {
        this.tokenVerifier = tokenVerifier;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        String authorizationHeader = request.getHeader(HttpHeaders.AUTHORIZATION);
        if (!StringUtils.hasText(authorizationHeader) || !authorizationHeader.startsWith("Bearer ")) {
            writeUnauthorized(response, "missing_bearer_token");
            return false;
        }

        String idToken = authorizationHeader.substring("Bearer ".length()).trim();
        if (!StringUtils.hasText(idToken)) {
            writeUnauthorized(response, "missing_bearer_token");
            return false;
        }

        try {
            AuthenticatedUser authenticatedUser = tokenVerifier.verify(idToken);
            request.setAttribute(AUTHENTICATED_USER_REQUEST_ATTRIBUTE, authenticatedUser);
            return true;
        } catch (FirebaseAuthException ex) {
            writeUnauthorized(response, "invalid_firebase_token");
            return false;
        }
    }

    private void writeUnauthorized(HttpServletResponse response, String reason) throws Exception {
        response.setStatus(HttpStatus.UNAUTHORIZED.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.getWriter().write("""
            {"status":"unauthorized","reason":"%s"}
            """.formatted(reason));
    }
}
