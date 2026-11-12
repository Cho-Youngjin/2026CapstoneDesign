package com.travelfootsteps.route;

import com.fasterxml.jackson.annotation.JsonValue;

// 복원한 구간의 종류(설계 6-1). estimated는 GPS가 없던 10분 이상의 공백(지하철 등)을 최단경로로 이은 것이다.
// @JsonValue: 응답 JSON에 이 enum을 소문자 이름으로 쓴다.
public enum SegmentKind {
    WALK("walk"),
    VEHICLE("vehicle"),
    ESTIMATED("estimated");

    private final String wireName;

    SegmentKind(String wireName) {
        this.wireName = wireName;
    }

    @JsonValue
    public String wireName() {
        return wireName;
    }
}
