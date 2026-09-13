package com.travelfootsteps.places;

// 앱(Plan F)이 쓰는 카테고리 값과 Google Places API가 쓰는 타입 문자열은 이름이 다르다
// (예: 우리 앱은 TOURIST, Google은 "tourist_attraction"). 이 enum이 그 매핑을 한 곳에
// 모아둔다 — 나중에 Google이 place type 이름을 바꾸거나 다른 지도 제공사로 교체하더라도,
// 이 매핑 하나만 고치면 되고 컨트롤러나 앱 쪽 계약(TOURIST 등)은 그대로 유지된다.
public enum PlaceCategory {
    TOURIST("tourist_attraction"),
    RESTAURANT("restaurant"),
    PHARMACY("pharmacy"),
    ATM("atm");

    private final String googlePlaceType;

    PlaceCategory(String googlePlaceType) {
        this.googlePlaceType = googlePlaceType;
    }

    public String googlePlaceType() {
        return googlePlaceType;
    }
}
