package com.travelfootsteps.places;

// PlacesClient 구현체가 돌려주는 내부 결과 타입. category를 문자열이 아니라 PlaceCategory
// enum으로 들고 있어서, "우리가 지금 어떤 카테고리를 조회했는지"가 타입으로 보장된다
// (오타로 잘못된 카테고리 문자열이 섞여 들어올 여지가 없다). 앱에 노출하는 JSON 계약은
// category를 문자열로 원하므로, 이 record를 그대로 응답에 쓰지 않고 PlaceResponse로
// 한 번 변환한다(PlaceResponse.java 참고).
public record PlaceResult(String id, String name, PlaceCategory category, String address, double lat, double lng) {
}
