package com.lovesaving.aiinsights.service;

import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseAuthException;
import com.google.firebase.auth.FirebaseToken;
import com.lovesaving.aiinsights.model.AuthenticatedUser;
import org.springframework.stereotype.Service;

@Service
public class FirebaseTokenVerifier {

    public AuthenticatedUser verify(String bearerToken) throws FirebaseAuthException {
        FirebaseToken token = FirebaseAuth.getInstance().verifyIdToken(bearerToken);
        return new AuthenticatedUser(
            token.getUid(),
            token.getEmail(),
            token.getName()
        );
    }
}
