package com.lovesaving.aiinsights.service;

import com.lovesaving.aiinsights.config.AiInsightsProperties;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseAuthException;
import com.google.firebase.auth.FirebaseToken;
import com.lovesaving.aiinsights.model.AuthenticatedUser;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

@Service
public class FirebaseTokenVerifier {

    public static final String DEBUG_USER_HEADER = "X-Debug-User-Id";
    private final AiInsightsProperties properties;

    public FirebaseTokenVerifier(AiInsightsProperties properties) {
        this.properties = properties;
    }

    public AuthenticatedUser verify(String bearerToken) throws FirebaseAuthException {
        FirebaseToken token = FirebaseAuth.getInstance().verifyIdToken(bearerToken);
        return new AuthenticatedUser(
            token.getUid(),
            token.getEmail(),
            token.getName()
        );
    }

    public boolean isLocalMode() {
        return properties.isLocalAuthMode();
    }

    public AuthenticatedUser resolveLocalUser(HttpServletRequest request) {
        String debugUserId = request.getHeader(DEBUG_USER_HEADER);
        String resolvedUid = StringUtils.hasText(debugUserId)
            ? debugUserId.trim()
            : properties.getLocalDebugUserId();

        return new AuthenticatedUser(
            resolvedUid,
            resolvedUid + "@local.dev",
            "Local Dev User"
        );
    }
}
