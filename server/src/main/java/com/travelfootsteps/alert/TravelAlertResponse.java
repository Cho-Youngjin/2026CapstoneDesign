package com.travelfootsteps.alert;

import java.time.OffsetDateTime;

// 컨트롤러가 엔티티를 그대로 노출하지 않고 이 DTO(record)로 변환해서 응답한다 — 응답 JSON
// 계약(Plan F가 이미 가정하고 있는 {id, level, region, title, issuedAt})을 엔티티 내부 구조
// 변경과 분리하기 위함이다.
public record TravelAlertResponse(Long id, int level, String region, String title, OffsetDateTime issuedAt) {
    public static TravelAlertResponse from(TravelAlert alert) {
        return new TravelAlertResponse(alert.getId(), alert.getLevel(), alert.getRegion(),
                alert.getTitle(), alert.getIssuedAt());
    }
}
