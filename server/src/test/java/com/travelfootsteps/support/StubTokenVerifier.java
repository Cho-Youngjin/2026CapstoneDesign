package com.travelfootsteps.support;

import com.travelfootsteps.auth.TokenVerifier;

import java.util.HashMap;
import java.util.Map;

/** 테스트에서 실제 Firebase 호출을 대체한다. 등록한 토큰만 유효하게 취급한다. */
public class StubTokenVerifier implements TokenVerifier {

    private final Map<String, String> tokenToUid = new HashMap<>();

    public void register(String idToken, String uid) {
        tokenToUid.put(idToken, uid);
    }

    @Override
    public String verifyAndGetUid(String idToken) {
        String uid = tokenToUid.get(idToken);
        if (uid == null) {
            throw new InvalidTokenException("unknown token: " + idToken, null);
        }
        return uid;
    }
}
