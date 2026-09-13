package com.travelfootsteps.translate;

// POST /api/translate의 응답 바디. 앱(Plan E)이 이미 이 필드명을 가정하고 있으므로
// 그대로 맞춘다. TranslationResult(엔진이 내부적으로 돌려준 값)를 그대로 노출하지 않고
// 이 record로 한 번 감싸는 이유는 TranslationResult.java의 주석과 같다 — API 계약과
// 엔진 내부 표현을 분리해서, 엔진이 바뀌어도 이 계약은 안 바뀌게 하기 위함이다.
public record TranslateResponse(String translatedText, String detectedSourceLanguage) {
    public static TranslateResponse from(TranslationResult result) {
        return new TranslateResponse(result.translatedText(), result.detectedSourceLanguage());
    }
}
