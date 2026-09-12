package com.travelfootsteps.externaldata;

// 공공데이터포털(data.go.kr) API 호출 실패 시 발생하는 예외다.
// 재시도 정책(1s/2s/4s 백오프로 최대 3회)을 거친 후에도 실패하면 이 예외를 던진다.
// 호출부(수집기/배치)는 이 예외를 잡아서 그 국가만 건너뛰고 다른 국가 처리를 계속할 수 있다.
public class ExternalApiException extends RuntimeException {
    public ExternalApiException(String message) {
        super(message);
    }

    public ExternalApiException(String message, Throwable cause) {
        super(message, cause);
    }
}
