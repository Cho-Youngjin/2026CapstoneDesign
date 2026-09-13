package com.travelfootsteps.alert;

import com.travelfootsteps.country.CountryRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

import java.util.List;

// CountryController와 마찬가지로 이 컨트롤러에는 로그인 확인 로직이 없다 — SecurityConfig가
// "/api/**는 인증 필요"로 이미 막아두었으므로, 인증되지 않은 요청은 필터 단계에서 401로
// 걸러지고 이 메서드까지 들어오지 않는다.
//
// 이 엔드포인트는 배치(DailyDataCollectionScheduler)가 이미 채워둔 DB를 그대로 읽기만 한다 —
// 요청 처리 경로에는 재시도 로직이 없다(재시도는 배치가 데이터를 수집할 때만 필요하다).
@RestController
@RequestMapping("/api/countries/{iso2}/alerts")
@RequiredArgsConstructor
public class TravelAlertController {

    private final CountryRepository countryRepository;
    private final TravelAlertRepository travelAlertRepository;

    @GetMapping
    public List<TravelAlertResponse> list(@PathVariable String iso2) {
        var country = countryRepository.findByIsoAlpha2(iso2.toUpperCase())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "국가를 찾을 수 없습니다: " + iso2));
        return travelAlertRepository.findByCountryIdOrderByIssuedAtDesc(country.getId())
                .stream().map(TravelAlertResponse::from).toList();
    }
}
