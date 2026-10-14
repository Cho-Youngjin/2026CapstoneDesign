package com.travelfootsteps.chat;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * STOMP 목적지 경로를 한곳에서 만들고 해석한다. 보내는 쪽(브로드캐스터, 위치 릴레이)과
 * 구독을 검사하는 쪽(RoomSubscriptionInterceptor)이 같은 규칙을 쓰도록 문자열을 여기에만 둔다.
 *
 * <p>구독 가능한 목적지는 아래 세 가지뿐이고, 모두 특정 방에 묶여 있다.
 * <ul>
 *     <li>{@code /topic/rooms/{roomId}/messages} — 새 메시지</li>
 *     <li>{@code /topic/rooms/{roomId}/read} — 읽음 위치 갱신 (Plan D Task 7)</li>
 *     <li>{@code /topic/group/{roomId}/location} — 실시간 위치 (Plan A Task 10에서 만든 경로 그대로)</li>
 * </ul>
 */
public final class RoomDestinations {

    // roomId는 숫자만, 최대 18자리(long 범위 안). 그 밖의 형태는 모두 매칭되지 않는다.
    private static final Pattern ROOM_TOPIC =
            Pattern.compile("^/topic/rooms/(\\d{1,18})/(messages|read)$");
    private static final Pattern LOCATION_TOPIC =
            Pattern.compile("^/topic/group/(\\d{1,18})/location$");

    private RoomDestinations() {
    }

    public static String messages(Long roomId) {
        return "/topic/rooms/" + roomId + "/messages";
    }

    public static String read(Long roomId) {
        return "/topic/rooms/" + roomId + "/read";
    }

    public static String location(Long roomId) {
        return "/topic/group/" + roomId + "/location";
    }

    /**
     * 구독 가능한 목적지면 그 방 id, 아니면 null.
     *
     * <p>"모르는 경로는 통과"가 아니라 "아는 경로만 허용"(허용 목록) 방식이다 — 호출부는 null이면
     * 구독을 거부한다. 앞으로 새 토픽을 추가할 때 여기에 패턴을 넣지 않으면 구독이 막히므로,
     * 권한 검사를 깜빡 빠뜨린 토픽이 열려 버리는 일이 생기지 않는다.
     */
    public static Long subscribableRoomId(String destination) {
        if (destination == null) {
            return null;
        }
        Matcher room = ROOM_TOPIC.matcher(destination);
        if (room.matches()) {
            return Long.parseLong(room.group(1));
        }
        Matcher location = LOCATION_TOPIC.matcher(destination);
        if (location.matches()) {
            return Long.parseLong(location.group(1));
        }
        return null;
    }

    /** 위치 릴레이가 받은 roomId 문자열을 방 id로 바꾼다. 숫자가 아니면 null. */
    public static Long parseRoomId(String roomId) {
        if (roomId == null || !roomId.matches("\\d{1,18}")) {
            return null;
        }
        return Long.parseLong(roomId);
    }
}
