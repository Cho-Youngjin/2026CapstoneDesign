package com.travelfootsteps.trip;

import com.travelfootsteps.country.Country;

import java.time.LocalDate;
import java.util.List;

// POST/GET/refresh 세 엔드포인트가 전부 같은 모양의 응답을 준다(계획서 Global Constraints 표에
// 명시된 계약). judgementStale은 GET/refresh에서만 의미가 있는 계산값이지만, POST(생성 직후)에도
// 필드 자체는 항상 내려준다 — 응답 스키마를 세 엔드포인트에서 하나로 유지하기 위해서다(생성
// 직후에는 방금 읽은 값으로 스냅샷을 만들었으므로 항상 false가 된다).
public record TripResponse(
        Long id,
        String countryIso2,
        String countryNameKo,
        LocalDate departDate,
        LocalDate returnDate,
        LocalDate passportExpiry,
        VisaResultResponse visaResult,
        List<TripTaskResponse> tasks,
        boolean judgementStale
) {
    public static TripResponse of(Trip trip, Country country, List<TripTask> tasks, boolean judgementStale) {
        return new TripResponse(
                trip.getId(),
                country.getIsoAlpha2(),
                country.getNameKo(),
                trip.getDepartDate(),
                trip.getReturnDate(),
                trip.getPassportExpiry(),
                VisaResultResponse.from(trip),
                tasks.stream().map(TripTaskResponse::from).toList(),
                judgementStale
        );
    }
}
