package com.travelfootsteps.places;

import java.util.List;

// "주변 장소를 검색한다"는 동작을 인터페이스 뒤에 둔다. TranslationClient와 달리 이 프로젝트는
// Places를 다른 제공사로 교체할 계획을 갖고 있지는 않다 — 지금 구현체는 GooglePlacesClient
// 하나뿐이다. 그럼에도 인터페이스로 분리해두는 이유는 auth 패키지의 TokenVerifier와 같다:
// 컨트롤러 테스트(PlacesControllerTest)가 실제 Google 서버에 네트워크로 요청을 보내지 않고도
// 이 인터페이스의 Mockito 목(mock)으로 컨트롤러 로직만 빠르게 검증할 수 있게 하기 위함이다.
public interface PlacesClient {
    List<PlaceResult> nearby(double lat, double lng, int radiusMeters, PlaceCategory category);
}
