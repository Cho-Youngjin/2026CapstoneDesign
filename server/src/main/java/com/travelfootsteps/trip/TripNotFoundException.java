package com.travelfootsteps.trip;

// 존재하지 않는 여행이거나(id 자체가 없음), 다른 사용자 소유라 존재를 감춰야 하는 경우에 던진다.
// 두 경우를 같은 예외/같은 404로 처리하는 것이 의도적이다 — 403으로 응답하면 "이 id는 존재는
// 하는데 내 것이 아니다"라는 정보를 노출하게 된다.
public class TripNotFoundException extends RuntimeException {
    public TripNotFoundException(Long id) {
        super("여행 계획을 찾을 수 없습니다: " + id);
    }
}
