package com.travelfootsteps.trip;

import com.travelfootsteps.country.Country;

import java.time.LocalDate;

// 여행 목록(GET /api/trips) 응답의 한 줄이다. 상세 응답(TripResponse)과 달리 준비 일정·여권 정보를
// 빼고 목록 카드에 필요한 값만 담는다 — 목록을 그릴 때마다 여행마다 trip_task를 조회하지 않기 위해서다.
// record: 필드·생성자·getter·equals를 자동으로 만들어 주는 Java의 불변 데이터 클래스다. 컨트롤러가
// 이 객체를 반환하면 Jackson이 필드 이름을 그대로 JSON 키로 써서 직렬화한다(LocalDate는 "yyyy-MM-dd").
public record TripSummaryResponse(
        Long id,
        String countryIso2,
        String countryNameKo,
        LocalDate departDate,
        LocalDate returnDate,
        // 여행 생성(또는 새로고침) 시점에 trip 테이블에 굳혀 둔 판정 스냅샷 값이다 — 목록에서도
        // 재계산하지 않는다(V4__trip.sql 상단 주석과 같은 이유).
        String verdict
) {
    public static TripSummaryResponse of(Trip trip, Country country) {
        return new TripSummaryResponse(
                trip.getId(),
                country.getIsoAlpha2(),
                country.getNameKo(),
                trip.getDepartDate(),
                trip.getReturnDate(),
                trip.getVerdict()
        );
    }
}
