package com.travelfootsteps.support;

import com.travelfootsteps.route.GeoPoint;
import com.travelfootsteps.route.OsrmClient;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;

/**
 * OsrmClient의 test 프로필 전용 no-op 스텁. StubPlacesClient와 같은 이유로 존재한다 —
 * HttpOsrmClient는 @Profile("!test")라 test 프로필에는 등록되지 않으므로, RouteController를
 * 컴포넌트 스캔하는 @SpringBootTest들이 이 빈 없이는 컨텍스트를 못 띄운다.
 */
@Component
@Profile("test")
public class StubOsrmClient implements OsrmClient {
    @Override
    public Optional<GeoPoint> nearest(String country, GeoPoint point, double maxDistanceMeters) {
        return Optional.empty();
    }

    @Override
    public List<GeoPoint> route(String country, GeoPoint from, GeoPoint to) {
        return List.of();
    }

    @Override
    public List<GeoPoint> match(String country, List<GeoPoint> points) {
        return List.of();
    }
}
