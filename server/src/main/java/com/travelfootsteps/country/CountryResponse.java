package com.travelfootsteps.country;

// 이건 Spring 애너테이션이 아니라 순수 자바 record이지만, 스프링 웹 계층에서 중요한 역할을 한다:
// 컨트롤러가 Country 엔티티를 그대로 리턴하지 않고 이 DTO(응답 전용 객체)로 한 번 변환해서 내보낸다.
// 이렇게 분리하는 이유는, DB 테이블(엔티티)에 나중에 컬럼이 추가/변경돼도 API가 실제로 클라이언트에게
// 보내는 JSON 모양(계약)은 여기서 명시한 필드로 고정되어 영향을 안 받게 하기 위해서다.
public record CountryResponse(
        String isoAlpha2,
        String nameKo,
        String nameEn,
        String continent,
        String tier
) {
    public static CountryResponse from(Country country) {
        return new CountryResponse(
                country.getIsoAlpha2(),
                country.getNameKo(),
                country.getNameEn(),
                country.getContinent(),
                country.getTier()
        );
    }
}
