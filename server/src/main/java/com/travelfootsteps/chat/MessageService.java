package com.travelfootsteps.chat;

import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * 메시지 보내기와 조회. 권한 검사는 모두 {@link RoomService#requireMember}를 거친다.
 *
 * <p>보내기 흐름: 멤버 확인 → 메시지 저장 → 방의 최근 메시지 정보 갱신 → (커밋 후) 실시간 전송.
 * 실시간 전송은 여기서 직접 하지 않고 이벤트로 넘긴다 — 이유는 {@link ChatMessageBroadcaster} 참고.
 */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class MessageService {

    static final int DEFAULT_PAGE_SIZE = 30;
    static final int MAX_PAGE_SIZE = 50;

    private final RoomService roomService;
    private final ChatRoomRepository roomRepository;
    private final ChatMessageRepository messageRepository;
    private final ApplicationEventPublisher eventPublisher;

    @Transactional
    public MessageResponse sendText(Long roomId, String uid, String text) {
        roomService.requireMember(roomId, uid);
        ChatRoom room = roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);

        ChatMessage message = messageRepository.save(ChatMessage.text(roomId, uid, text));
        room.recordLastMessage(message); // 같은 트랜잭션의 변경 감지로 함께 저장된다

        MessageResponse response = MessageResponse.of(message);
        eventPublisher.publishEvent(new MessageSentEvent(response));
        return response;
    }

    /**
     * 최신순(id 내림차순) 메시지 목록.
     *
     * @param beforeId null이면 가장 최근부터, 값이 있으면 그 id보다 오래된 것부터
     * @param size     요청 개수. 1~{@value #MAX_PAGE_SIZE} 범위를 벗어나면 그 범위로 맞춘다
     *                 (오류로 거부하기보다, 앱이 큰 값을 보내도 서버가 감당 가능한 양만 준다)
     */
    public List<MessageResponse> messages(Long roomId, String uid, Long beforeId, int size) {
        roomService.requireMember(roomId, uid);
        PageRequest limit = PageRequest.of(0, Math.clamp(size, 1, MAX_PAGE_SIZE));
        List<ChatMessage> messages = beforeId == null
                ? messageRepository.findByRoomIdOrderByIdDesc(roomId, limit)
                : messageRepository.findByRoomIdAndIdLessThanOrderByIdDesc(roomId, beforeId, limit);
        return messages.stream().map(MessageResponse::of).toList();
    }
}
