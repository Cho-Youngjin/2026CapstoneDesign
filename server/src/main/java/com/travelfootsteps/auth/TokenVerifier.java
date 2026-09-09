package com.travelfootsteps.auth;

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
