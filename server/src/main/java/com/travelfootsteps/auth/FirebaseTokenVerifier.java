package com.travelfootsteps.auth;

import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseAuthException;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile("!test")
@RequiredArgsConstructor
public class FirebaseTokenVerifier implements TokenVerifier {

    private final FirebaseAuth firebaseAuth;

    @Override
    public String verifyAndGetUid(String idToken) {
        try {
            return firebaseAuth.verifyIdToken(idToken).getUid();
        } catch (FirebaseAuthException e) {
            throw new InvalidTokenException("Firebase ID Token 검증 실패", e);
        }
    }
}
