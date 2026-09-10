package com.travelfootsteps.auth;

// "토큰을 검증해서 uid를 뽑아낸다"는 동작을 인터페이스 뒤에 숨겨둔 것이다.
// 이렇게 하는 이유: 실제 구현체(FirebaseTokenVerifier)는 진짜 Firebase 서버에 네트워크로
// 문의해야 하는데, 컨트롤러 테스트에서까지 매번 실제 Firebase를 호출하면 테스트가 느려지고
// 인터넷/키가 없으면 실패한다. 그래서 테스트에서는 이 인터페이스의 가짜 구현체(StubTokenVerifier)를
// 대신 끼워 넣어서, "Firebase가 뭐라고 답했다고 치고" 로직만 빠르게 검증한다.
public interface TokenVerifier {

    /**
     * Firebase ID Token을 검증하고 uid를 반환한다.
     *
     * @throws InvalidTokenException 토큰이 유효하지 않은 경우
     */
    String verifyAndGetUid(String idToken);

    class InvalidTokenException extends RuntimeException {
        public InvalidTokenException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
