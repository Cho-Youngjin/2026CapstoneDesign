package com.travelfootsteps.country;

import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

// 이 컨트롤러에는 로그인 확인 로직이 전혀 없다 — SecurityConfig가 "/api/**는 인증 필요"로
// 이미 막아두었기 때문에, 인증되지 않은 요청은 이 메서드까지 들어오지도 못하고 필터 단계에서
// 401로 걸러진다. 컨트롤러는 "인증된 사용자에게 무엇을 보여줄까"만 신경 쓰면 된다.
@RestController
@RequestMapping("/api/countries")
@RequiredArgsConstructor // Lombok: 두 리포지토리를 받는 생성자를 자동 생성 (생성자 주입)
public class CountryController {

    private final CountryRepository countryRepository;
    private final ChecklistTemplateRepository checklistTemplateRepository;

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

    // GET /api/countries/{iso2} — 국가 상세 정보(플러그 타입, 전압, 통화 등)를 하나 돌려준다.
    @GetMapping("/{iso2}")
    public CountryDetailResponse detail(@PathVariable String iso2) {
        return CountryDetailResponse.from(findCountryOrThrow(iso2));
    }

    // GET /api/countries/{iso2}/checklist — 이 국가에 적용되는 "공통 템플릿"을 읽기 전용으로
    // 보여준다. 여기서 반환하는 목록에는 checked 상태가 없다(애초에 사용자별 상태가 아니라
    // 국가별 공통 정의이기 때문) — 사용자가 실제로 체크하는 화면은 여행을 만든 뒤
    // GET/POST /api/trips/{tripId}/checklist(TripController)가 담당한다. 이 엔드포인트는
    // "여행을 만들기 전 미리보기"나 앱의 정적 안내 화면에 쓰인다.
    @GetMapping("/{iso2}/checklist")
    public List<ChecklistTemplateResponse> checklist(@PathVariable String iso2) {
        Country country = findCountryOrThrow(iso2);
        return checklistTemplateRepository
                .findByCountryIdIsNullOrCountryIdOrderByPriorityAsc(country.getId())
                .stream().map(ChecklistTemplateResponse::from).toList();
    }

    private Country findCountryOrThrow(String iso2) {
        return countryRepository.findByIsoAlpha2(iso2.toUpperCase())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "국가를 찾을 수 없습니다: " + iso2));
    }
}
