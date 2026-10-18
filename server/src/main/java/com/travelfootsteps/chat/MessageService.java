package com.travelfootsteps.chat;

import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

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

    /**
     * 사진 한 장의 최대 크기(5MB). application.yml의 multipart 한도(max-file-size)도 같은 값이라 실제 요청은 그쪽에서
     * 먼저 413으로 막히지만, 한도 설정이 바뀌거나 빠져도 여기서 한 번 더 막는다.
     */
    static final int MAX_IMAGE_BYTES = 5 * 1024 * 1024;

    private final RoomService roomService;
    private final ChatRoomRepository roomRepository;
    private final ChatMessageRepository messageRepository;
    private final ApplicationEventPublisher eventPublisher;
    private final ChatImageStorage imageStorage;

    @Transactional
    public MessageResponse sendText(Long roomId, String uid, String text) {
        roomService.requireMember(roomId, uid); // 멤버 행이 있으면 방도 있다(FK)
        return saveAndAnnounce(ChatMessage.text(roomId, uid, text));
    }

    /**
     * 사진을 보낸다(Plan D Task 6). 흐름: 멤버 확인 → 크기·형식 검사 → <b>파일 저장 → 메시지 저장</b> → (커밋 후) 실시간 전송.
     *
     * <p>파일과 DB가 어긋나지 않게: 파일을 먼저 저장하고, 이 트랜잭션이 <b>커밋되지 못하면</b>(메시지 저장 실패, 커밋 실패
     * 모두) 방금 저장한 파일을 지운다. "커밋되지 못하면"을 아는 방법이 아래의 트랜잭션 동기화 콜백이다 — 메서드 안의
     * try/catch로는 메서드가 끝난 뒤 커밋 단계에서 나는 실패를 잡을 수 없다. 거꾸로 메시지를 먼저 저장하면, 파일 저장이
     * 실패했을 때 열리지 않는 사진 메시지가 실시간으로 먼저 퍼질 수 있다.
     */
    @Transactional
    public MessageResponse sendImage(Long roomId, String uid, byte[] bytes) {
        roomService.requireMember(roomId, uid);
        if (bytes.length == 0) {
            throw new InvalidChatImageException();
        }
        if (bytes.length > MAX_IMAGE_BYTES) {
            throw new ChatImageTooLargeException();
        }
        ChatImageFormat format = ChatImageFormat.detect(bytes).orElseThrow(UnsupportedChatImageException::new);

        String path = imageStorage.save(bytes, format);
        // TransactionSynchronization: 지금 진행 중인 트랜잭션이 끝날 때(커밋이든 롤백이든) 스프링이 불러 주는 콜백.
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCompletion(int status) {
                if (status != STATUS_COMMITTED) {
                    imageStorage.delete(path);
                }
            }
        });
        return saveAndAnnounce(ChatMessage.image(roomId, uid, path));
    }

    /**
     * 사진 내려받기. 내가 그 방의 멤버이고, 메시지가 <b>그 방의 사진 메시지</b>일 때만 준다 — 다른 방의 메시지 id를
     * 경로에 넣거나 글자 메시지 id를 넣으면, 내가 그 방들의 멤버여도 없는 것(404)으로 본다.
     */
    public ChatImage loadImage(Long roomId, String uid, Long messageId) {
        roomService.requireMember(roomId, uid);
        ChatMessage message = messageRepository.findById(messageId)
                .filter(m -> m.getRoomId().equals(roomId) && m.getType() == MessageType.IMAGE)
                .orElseThrow(RoomNotFoundException::new);
        String path = message.getImagePath();
        ChatImageFormat format = ChatImageFormat.fromExtension(path).orElseThrow(RoomNotFoundException::new);
        return new ChatImage(imageStorage.load(path), format.contentType);
    }

    /** 내려받기 응답에 쓸 사진 바이트와 형식. */
    public record ChatImage(byte[] bytes, String contentType) {
    }

    private MessageResponse saveAndAnnounce(ChatMessage unsaved) {
        ChatMessage message = messageRepository.save(unsaved);
        // 같은 트랜잭션 안의 UPDATE라 메시지 저장이 롤백되면 이 갱신도 함께 롤백된다.
        // 더 새로운 메시지가 이미 기록돼 있으면 아무것도 바꾸지 않는다(동시 전송 대비).
        roomRepository.recordLastMessage(message.getRoomId(), message.getId(), ChatRoom.previewOf(message),
                message.getCreatedAt());

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
