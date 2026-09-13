package com.travelfootsteps.trip;

// 응답 DTO(record)다. 의도적으로 VisaJudgement가 아니라 Trip에서 값을 뽑아 만든다 — 이 프로젝트의
// 핵심 설계는 "GET/refresh 응답이 항상 trip 테이블에 저장된 스냅샷 컬럼에서만 나온다"는 것이라,
// VisaJudgement를 직접 받는 변환 경로를 따로 두면 실수로 라이브 재계산 결과를 응답에 섞어 보내는
// 문을 열어두게 된다. POST(생성)/refresh도 판정을 계산한 즉시 Trip.applyJudgementSnapshot()으로
// 먼저 저장한 뒤, 이 from(Trip)으로 응답을 만든다 — 세 엔드포인트(POST/GET/refresh) 모두 결국
// "저장된 스냅샷을 읽어서 응답한다"는 동일한 경로를 타게 하기 위함이다.
public record VisaResultResponse(
        String verdict,
        int stayDays,
        Integer visaFreeDays,
        boolean passportOk,
        Integer passportValidityMonths,
        Integer passportShortfallDays
) {
    public static VisaResultResponse from(Trip trip) {
        return new VisaResultResponse(
                trip.getVerdict(),
                trip.getStayDays(),
                trip.getVisaFreeDays(),
                trip.isPassportOk(),
                trip.getPassportValidityMonths(),
                trip.getPassportShortfallDays()
        );
    }
}
