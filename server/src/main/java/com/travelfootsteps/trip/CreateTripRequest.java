package com.travelfootsteps.trip;

import jakarta.validation.constraints.AssertTrue;
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
    // Jakarta Bean Validation은 getter 스타일 메서드(is-prefixed boolean)를 하나의 제약으로
    // 인식한다 — record의 컴팩트 생성자 밖에서 필드 간 교차 검증(cross-field validation)을 걸 때
    // 쓰는 표준 패턴이다. false를 반환하면 "returnDate는 departDate보다 앞설 수 없습니다"라는
    // 메시지로 위반이 등록되고, @Valid가 컨트롤러 본문 실행 전에 400으로 막는다. null 체크를
    // 먼저 하는 이유: @NotNull 위반과 이 위반이 동시에 나더라도(둘 다 400 이유가 되므로 무해하지만)
    // NPE로 다른 위반 메시지들이 통째로 가려지는 것을 막기 위함이다.
    @AssertTrue(message = "returnDate는 departDate보다 앞설 수 없습니다")
    public boolean isReturnAfterDepart() {
        return departDate == null || returnDate == null || !returnDate.isBefore(departDate);
    }
}
