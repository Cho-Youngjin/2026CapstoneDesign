package com.travelfootsteps.support;

import com.travelfootsteps.places.PlaceCategory;
import com.travelfootsteps.places.PlaceResult;
import com.travelfootsteps.places.PlacesClient;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * PlacesClient의 test 프로필 전용 no-op 스텁. GooglePlacesClient는 @Profile("!test")라
 * test 프로필에서는 등록되지 않으므로, PlacesController를 컴포넌트 스캔하는 모든 @SpringBootTest가
 * (이 기능을 직접 테스트하지 않는 것들까지 포함해서) 이 빈 없이는 컨텍스트를 못 띄운다. 그 테스트들이
 * 매번 목(mock)을 직접 등록하지 않아도 되도록 test 프로필에서 전역으로 스캔되는 빈으로 등록한다.
 * PlacesControllerTest 자신은 @WebMvcTest 슬라이스라 이 빈과 무관하게 자기만의 Mockito mock을 쓴다.
 */
@Component
@Profile("test")
public class StubPlacesClient implements PlacesClient {
    @Override
    public List<PlaceResult> nearby(double lat, double lng, int radiusMeters, PlaceCategory category) {
        return List.of();
    }
}
