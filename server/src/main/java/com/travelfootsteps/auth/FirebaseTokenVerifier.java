package com.travelfootsteps.auth;

import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseAuthException;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

// TokenVerifier 인터페이스의 "진짜" 구현체. 실제로 Firebase 서버와 통신해서 토큰을 검증한다.
// @Component: 스프링에게 "이 클래스의 인스턴스를 빈으로 관리해줘"라고 알리는 애너테이션이다.
// (@Service, @Repository, @RestController도 전부 @Component의 특수한 형태다.)
// @Profile("!test")로 FirebaseConfig와 마찬가지로 테스트 환경에서는 이 빈이 아예 생기지 않는다 —
// 그 자리는 테스트 코드가 직접 등록하는 StubTokenVerifier가 대신 채운다.
@Component
@Profile("!test")
@RequiredArgsConstructor
public class FirebaseTokenVerifier implements TokenVerifier {

    // 생성자 주입: FirebaseConfig가 만들어둔 FirebaseAuth 빈을 스프링이 자동으로 넣어준다.
    private final FirebaseAuth firebaseAuth;

    @Override
    public String verifyAndGetUid(String idToken) {
        try {
            // 여기서 실제로 Firebase 서버에 토큰이 유효한지 물어보고(서명·만료시간 검증 포함),
            // 유효하면 토큰 안에 들어있는 사용자 고유 ID(uid)를 꺼내온다.
            return firebaseAuth.verifyIdToken(idToken).getUid();
        } catch (FirebaseAuthException e) {
            // 검증 실패(위조·만료 등)는 우리가 정의한 예외로 감싸서 던진다.
            // 이렇게 하면 이 클래스를 호출하는 쪽(FirebaseAuthFilter)이 Firebase 전용 예외 타입을
            // 몰라도 되고, TokenVerifier 인터페이스에만 의존하면 된다.
            throw new InvalidTokenException("Firebase ID Token 검증 실패", e);
        }
    }
}
