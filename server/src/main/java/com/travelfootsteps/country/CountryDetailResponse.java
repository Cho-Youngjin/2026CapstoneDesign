package com.travelfootsteps.country;

// GET /api/countries/{iso2}의 응답이다. country 테이블의 컬럼을 (스네이크 -> 카멜케이스로)
// 그대로 노출한다 — 목록용 CountryResponse보다 필드가 많은, 상세 화면 전용 DTO다.
public record CountryDetailResponse(
        String isoAlpha2, String isoAlpha3, String nameKo, String nameEn, String continent, String tier,
        String plugTypes, Integer voltageV, Integer frequencyHz, String currencyCode,
        String cardAcceptance, Integer powerBankWhLimit
) {
    public static CountryDetailResponse from(Country c) {
        return new CountryDetailResponse(
                c.getIsoAlpha2(), c.getIsoAlpha3(), c.getNameKo(), c.getNameEn(), c.getContinent(), c.getTier(),
                c.getPlugTypes(), c.getVoltageV(), c.getFrequencyHz(), c.getCurrencyCode(),
                c.getCardAcceptance(), c.getPowerBankWhLimit()
        );
    }
}
