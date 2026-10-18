package com.travelfootsteps.chat;

import lombok.RequiredArgsConstructor;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * 저장된 메시지를 그 방 구독자들에게 실시간으로 보낸다.
 *
 * <p><b>왜 커밋 후(AFTER_COMMIT)인가</b>: 저장과 같은 트랜잭션 안에서 바로 보내면, 그 뒤에
 * 무언가 실패해 롤백됐을 때 상대 화면에는 DB에 없는 메시지가 이미 떠 있게 된다. 반대로 커밋이
 * 끝난 뒤에만 보내면 "화면에 보인 메시지는 반드시 저장돼 있다"가 보장된다. 커밋 후 전송이
 * 실패하는 경우(서버가 그 순간 죽는 등)에는 메시지가 저장만 되고 실시간으로 안 갈 수 있지만,
 * 앱이 재연결할 때 REST로 빈 구간을 다시 받아 오므로(Plan D Task 4) 결국 보이게 된다.
 *
 * <p>트랜잭션이 롤백되면 이 리스너는 아예 호출되지 않는다.
 */
@Component
@RequiredArgsConstructor
class ChatMessageBroadcaster {

    private final SimpMessagingTemplate messagingTemplate;

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onMessageSent(MessageSentEvent event) {
        MessageResponse message = event.message();
        messagingTemplate.convertAndSend(RoomDestinations.messages(message.roomId()), message);
    }
}
