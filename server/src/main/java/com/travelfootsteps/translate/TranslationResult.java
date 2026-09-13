package com.travelfootsteps.translate;

// TranslationClient 구현체가 돌려주는 내부 결과 타입이다. 앱에 그대로 노출하는
// TranslateResponse(§ 아래 참고)와 굳이 분리해둔 이유: 이 record는 "번역 엔진이 무엇을
// 돌려줬는지"만 표현하고, TranslateResponse는 "우리 API가 앱에 어떤 JSON을 약속했는지"를
// 표현한다. 두 책임을 하나로 합치면, 나중에 엔진을 바꿨을 때(예: LLM 응답 필드가 다르게 생겼을 때)
// API 계약까지 함께 흔들릴 위험이 생긴다.
public record TranslationResult(String translatedText, String detectedSourceLanguage) {
}
