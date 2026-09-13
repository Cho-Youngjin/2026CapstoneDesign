package com.travelfootsteps.translate;

// "텍스트를 번역한다"는 동작을 인터페이스 뒤에 숨겨둔 것이다. auth 패키지의 TokenVerifier와
// 완전히 같은 이유다: 지금은 Google Cloud Translation(NMT, 통계·신경망 기반 기계번역)을
// 구현체(GoogleTranslateClient)로 쓰지만, 이 프로젝트는 나중에 더 자연스러운 번역이 필요해지면
// LLM(거대언어모델) 기반 번역기로 교체할 계획이다(스펙 §4, §12). 컨트롤러(TranslateController)가
// 이 인터페이스에만 의존하면, 그 교체는 "이 인터페이스를 구현하는 새 빈을 하나 더 만들고
// 스프링 설정에서 어떤 빈을 쓸지만 바꾸는" 일이 되어 컨트롤러 코드는 한 줄도 손댈 필요가 없다.
// 테스트에서도 실제 Google API를 부르지 않고 이 인터페이스의 Mockito 목(mock)을 끼워 넣어
// 컨트롤러 로직만 빠르게 검증할 수 있다.
public interface TranslationClient {

    /**
     * 텍스트를 targetLanguage로 번역한다.
     *
     * @param sourceLanguage 원문 언어(ISO 639-1). null이면 구현체가 자동 감지한다.
     */
    TranslationResult translate(String text, String targetLanguage, String sourceLanguage);
}
