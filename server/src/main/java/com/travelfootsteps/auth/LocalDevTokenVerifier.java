package com.travelfootsteps.auth;

import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

// 로컬 개발 전용 TokenVerifier. 앱의 main_dev.dart(DevAuthRepository)가 보내는 더미 토큰만
// 받아 준다 — Firebase 서비스 계정 키 없이 Spring 서버를 띄워 앱과 붙여 보기 위한 용도다.
// @Profile("local")이라 평소 실행(프로필 없음)이나 운영에서는 이 빈이 생기지 않고,
// 그때는 FirebaseTokenVerifier가 그대로 쓰인다. 실행: SPRING_PROFILES_ACTIVE=local
@Component
@Profile("local")
public class LocalDevTokenVerifier implements TokenVerifier {

    static final String DEV_TOKEN = "dev-fake-token";
    static final String DEV_UID = "dev-user";

    @Override
    public String verifyAndGetUid(String idToken) {
        if (!DEV_TOKEN.equals(idToken)) {
            throw new InvalidTokenException("local 프로필은 개발용 더미 토큰만 허용한다", null);
        }
        return DEV_UID;
    }
}
