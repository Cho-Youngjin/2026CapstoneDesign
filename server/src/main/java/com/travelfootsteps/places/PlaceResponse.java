package com.travelfootsteps.places;

// GET /api/places/nearby의 응답 원소. 앱(Plan F)이 이미 이 필드명을 가정하고 있으므로
// 그대로 맞춘다. category는 PlaceResult에서는 enum이지만 여기서는 문자열(enum 상수 이름)로
// 노출한다 — JSON 계약(Global Constraints 표)이 문자열을 요구하기 때문이다.
public record PlaceResponse(String id, String name, String category, String address, double lat, double lng) {
    public static PlaceResponse from(PlaceResult r) {
        return new PlaceResponse(r.id(), r.name(), r.category().name(), r.address(), r.lat(), r.lng());
    }
}
