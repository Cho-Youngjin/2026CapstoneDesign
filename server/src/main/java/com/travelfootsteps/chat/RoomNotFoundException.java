package com.travelfootsteps.chat;

/**
 * 방이 없거나, 있어도 요청한 사람이 멤버가 아닐 때. 두 경우를 일부러 구분하지 않는다 —
 * 403을 주면 "그 id의 방은 존재한다"는 사실을 알려주게 되므로 둘 다 404로 답한다
 * (TripNotFoundException과 같은 원칙).
 */
public class RoomNotFoundException extends RuntimeException {

    public RoomNotFoundException() {
        super("채팅방을 찾을 수 없습니다");
    }
}
