package com.travelfootsteps.route;

// 복원 안에서 쓰는 지나간 점 하나. 측위 점이면 startT = endT이고, 머문 곳이면 그 중심이 [도착, 출발]을 차지한다.
// 공백은 앞 점의 endT와 다음 점의 startT 사이로 잰다 — 머문 시간 자체를 공백으로 보지 않기 위해서다.
//  - accuracy       : 정확도(m). 모르면 null
//  - stepsSincePrev : 직전 점 이후 걸음 수. 모르면 null
//  - state          : 측위 때 정책 상태(still·walking·otherMotion·vehicle·unknown). 모르면 null
record Waypoint(long startT, long endT, GeoPoint point, Double accuracy, Integer stepsSincePrev, String state) {

    boolean isVehicle() {
        return "vehicle".equals(state);
    }
}
