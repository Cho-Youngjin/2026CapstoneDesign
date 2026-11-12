package com.travelfootsteps.trip;

import com.travelfootsteps.country.Country;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;

// record + jakarta.validation 애너테이션: @Valid와 함께 컨트롤러 파라미터에 쓰이면, 스프링이
// 요청 본문을 이 레코드로 역직렬화한 뒤 애너테이션 조건을 검사한다. 하나라도 위반하면
// 컨트롤러 메서드 본문이 실행되기 전에 MethodArgumentNotValidException이 던져지고, 스프링
// 기본 설정상 400 Bad Request로 응답된다.
//
// passportExpiry에는 @NotNull이 없다 — 국내 여행(countryIso2 = "KR")은 여권 만료일을 받지 않는다(설계 9-1).
// 해외 여행에 꼭 있어야 한다는 규칙은 아래 isPassportExpiryGivenUnlessDomestic()이 대신 검사한다.
public record CreateTripRequest(
        @NotBlank String countryIso2,
        @NotNull LocalDate departDate,
        @NotNull LocalDate returnDate,
        LocalDate passportExpiry
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

    // 같은 @AssertTrue 패턴으로 "해외 여행이면 여권 만료일이 필수"를 검사한다. 국가 코드와 여권 만료일 두 필드의
    // 관계라 필드 하나에 붙이는 @NotNull로는 표현할 수 없다. 위반하면 위와 똑같이 400이다.
    @AssertTrue(message = "해외 여행은 passportExpiry가 필요합니다")
    public boolean isPassportExpiryGivenUnlessDomestic() {
        return passportExpiry != null || Country.isHomeIso2(countryIso2);
    }
}
