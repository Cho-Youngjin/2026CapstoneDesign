package com.travelfootsteps.location;

import lombok.RequiredArgsConstructor;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;

import java.security.Principal;

/**
 * 그룹 실시간 위치공유의 서버 릴레이. 좌표를 저장하지 않고 같은 방을 구독 중인
 * 클라이언트에게만 즉시 전달한다(스펙 §3, §6-④ — Firestore/Postgres에 5초 간격
 * 좌표를 계속 쓰면 무료 티어 쓰기 쿼터를 금방 소진하므로 애초에 저장하지 않는 설계다).
 *
 * 발신자 uid는 클라이언트가 자기 신고로 보내지 않는다(LocationMessage에는 uid 필드
 * 자체가 없다) — StompAuthChannelInterceptor가 STOMP CONNECT 시점에 Firebase 토큰을
 * 검증해 세션에 고정해 둔 Principal에서 서버가 직접 채운다. 이 메서드 시그니처의
 * Principal 파라미터는 Spring Messaging이 그 세션 고정값을 자동으로 주입해 준 것이며,
 * 클라이언트가 이 값을 조작할 수 있는 경로는 없다(위조 방지).
 *
 * 의도적으로 생략한 것 — 그룹 멤버십(Firestore participants[]) 검증: 매 SEND/SUBSCRIBE마다
 * Firestore를 왕복 조회하는 비용과 지연을 피하기 위해, v1은 "유효한 로그인 사용자이면서
 * roomId(비공개 초대 코드로만 얻는 값)를 아는 사람"까지만 최소 보장한다. 이 트레이드오프의
 * 전제(초대 코드 목록이 열람 불가능해야 함)와 잔여 리스크는 Plan A Task 10 브리프에 기록돼
 * 있다 — 여기서 조용히 빠뜨린 게 아니라 의도된 범위 판단이다.
 */
@Controller
@RequiredArgsConstructor
public class LocationRelayController {

    private final SimpMessagingTemplate messagingTemplate;

    @MessageMapping("/location")
    public void relay(LocationMessage message, Principal principal) {
        if (principal == null || message.roomId() == null || message.roomId().isBlank()) {
            return; // 인증되지 않았거나(이론상 인터셉터가 이미 걸렀어야 함) 방 정보가 없는 프레임은 조용히 버린다
        }
        LocationBroadcast broadcast = new LocationBroadcast(
                principal.getName(), message.lat(), message.lng(), message.ts());
        messagingTemplate.convertAndSend("/topic/group/" + message.roomId() + "/location", broadcast);
    }
}
