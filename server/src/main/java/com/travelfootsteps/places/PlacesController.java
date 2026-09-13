package com.travelfootsteps.places;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

// TranslateController와 같은 이유로 존재하는 얇은 프록시 컨트롤러다 — Google Places API 키를
// 앱(APK)에 넣지 않기 위해서다. 컨트롤러는 PlacesClient 인터페이스에만 의존한다.
@RestController
@RequestMapping("/api/places")
@RequiredArgsConstructor
public class PlacesController {

    private final PlacesClient placesClient;

    // @RequestParam: 쿼리 파라미터(?lat=...&lng=...)를 메서드 파라미터로 바인딩한다.
    // category는 PlaceCategory enum 타입이라, 스프링이 쿼리 문자열("RESTAURANT" 등)을
    // 자동으로 PlaceCategory.valueOf(...)로 변환한다 — 대소문자가 다르거나 정의되지 않은
    // 값이 오면 스프링이 자동으로 400 Bad Request를 응답한다(별도 처리 코드 불필요).
    @GetMapping("/nearby")
    public List<PlaceResponse> nearby(@RequestParam double lat, @RequestParam double lng,
                                       @RequestParam(defaultValue = "1000") int radius,
                                       @RequestParam PlaceCategory category) {
        return placesClient.nearby(lat, lng, radius, category)
                .stream().map(PlaceResponse::from).toList();
    }
}
