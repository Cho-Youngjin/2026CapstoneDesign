package com.travelfootsteps.country;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

// 이 컨트롤러에는 로그인 확인 로직이 전혀 없다 — SecurityConfig가 "/api/**는 인증 필요"로
// 이미 막아두었기 때문에, 인증되지 않은 요청은 이 메서드까지 들어오지도 못하고 필터 단계에서
// 401로 걸러진다. 컨트롤러는 "인증된 사용자에게 무엇을 보여줄까"만 신경 쓰면 된다.
@RestController
@RequestMapping("/api/countries")
@RequiredArgsConstructor // Lombok: countryRepository를 받는 생성자를 자동 생성 (생성자 주입)
public class CountryController {

    private final CountryRepository countryRepository;

    // GET /api/countries 요청을 처리한다. @RequestMapping의 "/api/countries"와 합쳐져
    // 최종 경로가 "/api/countries"가 된다.
    @GetMapping
    public List<CountryResponse> list() {
        // DB에서 Country 엔티티 목록을 이름 오름차순으로 가져온 뒤, 엔티티를 그대로 반환하지 않고
        // CountryResponse(DTO)로 하나씩 변환한다. 스프링이 리턴값을 자동으로 JSON 배열로 직렬화해준다.
        return countryRepository.findAllByOrderByNameKoAsc()
                .stream()
                .map(CountryResponse::from)
                .toList();
    }
}
