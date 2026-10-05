package com.travelfootsteps.route;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;

// 요청/응답 JSON의 {lat, lng} 좌표. 앱(Flutter)과의 계약이라 필드 이름을 바꾸면 안 된다.
public record GeoPoint(
        @DecimalMin("-90") @DecimalMax("90") double lat,
        @DecimalMin("-180") @DecimalMax("180") double lng
) {
}
