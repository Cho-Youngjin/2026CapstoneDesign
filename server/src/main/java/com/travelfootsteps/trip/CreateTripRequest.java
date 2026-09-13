package com.travelfootsteps.trip;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;

// record + jakarta.validation 애너테이션: @Valid와 함께 컨트롤러 파라미터에 쓰이면, 스프링이
// 요청 본문을 이 레코드로 역직렬화한 뒤 애너테이션 조건을 검사한다. 하나라도 위반하면
// 컨트롤러 메서드 본문이 실행되기 전에 MethodArgumentNotValidException이 던져지고, 스프링
// 기본 설정상 400 Bad Request로 응답된다.
public record CreateTripRequest(
        @NotBlank String countryIso2,
        @NotNull LocalDate departDate,
        @NotNull LocalDate returnDate,
        @NotNull LocalDate passportExpiry
) {
}
