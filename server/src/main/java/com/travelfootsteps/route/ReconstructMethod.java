package com.travelfootsteps.route;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

// 경로 복원 방법(설계 2026-11-07 6-2 표). JSON에서는 소문자 이름(osrm_match_radius 등)으로 주고받는다.
// @JsonValue는 Jackson(스프링이 JSON 변환에 쓰는 라이브러리)이 이 enum을 JSON으로 쓸 때 쓰는 값을,
// @JsonCreator는 JSON 문자열에서 enum을 만들 때 부르는 메서드를 정한다. 모르는 이름이면 예외가 나고,
// 스프링 MVC가 그것을 "요청 본문을 읽을 수 없음"으로 받아 400 Bad Request로 돌려준다.
public enum ReconstructMethod {
    STRAIGHT("straight"),
    NEAREST("nearest"),
    OSRM_MATCH("osrm_match"),
    OSRM_MATCH_RADIUS("osrm_match_radius"),
    HMM_STEPS("hmm_steps");

    private final String wireName;

    ReconstructMethod(String wireName) {
        this.wireName = wireName;
    }

    @JsonValue
    public String wireName() {
        return wireName;
    }

    @JsonCreator
    public static ReconstructMethod from(String value) {
        for (ReconstructMethod method : values()) {
            if (method.wireName.equals(value)) return method;
        }
        throw new IllegalArgumentException("알 수 없는 복원 방법: " + value);
    }
}
