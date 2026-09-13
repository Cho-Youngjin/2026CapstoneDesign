package com.travelfootsteps.location;

// 서버가 SUBSCRIBE /topic/group/{roomId}/location 구독자에게 내보내는 브로드캐스트 바디.
// Plan D(Flutter STOMP 클라이언트)가 이미 이 모양 {uid, lat, lng, ts}을 가정하고
// 파싱 코드를 작성해 두었다 — 필드 이름/순서를 바꾸면 클라이언트가 조용히 이벤트를 버린다.
public record LocationBroadcast(String uid, double lat, double lng, long ts) {
}
