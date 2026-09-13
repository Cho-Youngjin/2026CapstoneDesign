package com.travelfootsteps.translate;

import jakarta.validation.constraints.NotBlank;

// POST /api/translate의 요청 바디. @NotBlank(jakarta.validation)는 이 필드가 null이거나
// 공백만 있으면 안 된다는 제약이다. 컨트롤러 메서드 파라미터에 @Valid를 붙여야 이 제약이
// 실제로 검사되며, 위반 시 스프링이 자동으로 400 Bad Request를 응답한다.
// sourceLanguage는 일부러 @NotBlank를 붙이지 않았다 — 원문 언어를 모를 때(자동 감지 요청)
// null로 보내는 것이 정상 케이스이기 때문이다.
public record TranslateRequest(@NotBlank String text, @NotBlank String targetLanguage, String sourceLanguage) {
}
