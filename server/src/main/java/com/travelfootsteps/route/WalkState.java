package com.travelfootsteps.route;

import java.util.List;

// 앱이 내용을 해석하지 않고 다음 요청에 그대로 되돌려 보내는 값이다. 서버가 세션 상태를 들고
// 있지 않으므로 여러 사용자나 서버 재시작에도 안전하다. 필드 이름은 mock 서버 응답과 같다.
//  - heading   : 일본 쪽 마지막 진행 방향(도). 첫 요청에서는 null.
//  - krHeading : 직전 요청의 한국 진행 방향(도).
//  - trail     : 최근 지나온 점(5m 간격) — 되돌아가는지 판단하는 데 쓴다.
//  - turnSide  : 직전에 꺾은 쪽(+1/-1).
//  - ideal     : 한국 이동을 그대로 옮겼다면 도착했을 "이상 위치".
public record WalkState(Double heading, Double krHeading, List<GeoPoint> trail,
                        Integer turnSide, GeoPoint ideal) {
}
