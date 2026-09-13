package com.travelfootsteps.visa;

/**
 * 비자 판정 결과의 4가지 상태. {@code wireValue()}는 Plan B의 {@code VisaVerdict.wireValue}와
 * 문자 그대로 일치해야 한다 — 이 문자열은 API 응답으로 그대로 나가며 Plan B(별도 문서/앱)가
 * 이 정확한 문자열에 의존한다. 바꾸면 Plan B가 깨진다.
 */
public enum VisaVerdict {
    VISA_FREE_OK("VISA_FREE_OK"),
    VISA_FREE_EXCEEDED("VISA_FREE_EXCEEDED"),
    VISA_REQUIRED("VISA_REQUIRED"),
    UNVERIFIED("UNVERIFIED");

    private final String wireValue;

    VisaVerdict(String wireValue) {
        this.wireValue = wireValue;
    }

    public String wireValue() {
        return wireValue;
    }
}
