package com.travelfootsteps.embassy;

import com.travelfootsteps.country.CountryRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

// TravelAlertController와 동일한 패턴 — SecurityConfig가 인증을 이미 처리하므로 이 컨트롤러는
// "인증된 사용자에게 무엇을 보여줄까"만 신경 쓴다. 배치가 채워둔 DB를 읽기만 하고
// 재시도 로직은 없다(재시도는 배치 수집 경로에서만 필요).
@RestController
@RequestMapping("/api/countries/{iso2}/embassies")
@RequiredArgsConstructor
public class EmbassyController {

    private final CountryRepository countryRepository;
    private final EmbassyRepository embassyRepository;

    @GetMapping
    public List<EmbassyResponse> list(@PathVariable String iso2) {
        var country = countryRepository.findByIsoAlpha2(iso2.toUpperCase())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "국가를 찾을 수 없습니다: " + iso2));
        return embassyRepository.findByCountryId(country.getId())
                .stream().map(EmbassyResponse::from).toList();
    }
}
