package com.travelfootsteps.location;

// 클라이언트가 SEND /app/location으로 보내는 요청 바디(Plan D 계약 그대로).
// 의도적으로 uid 필드가 없다 — 발신자가 누구인지는 클라이언트의 자기 신고가 아니라
// StompAuthChannelInterceptor가 세션에 고정해 둔 Principal에서만 나온다(위조 방지).
// Jackson은 기본적으로 알 수 없는 JSON 필드를 조용히 무시하므로, 클라이언트가 여기에
// "uid"를 끼워 보내더라도 이 레코드로 역직렬화되는 순간 사라진다.
public record LocationMessage(String roomId, double lat, double lng, long ts) {
}
