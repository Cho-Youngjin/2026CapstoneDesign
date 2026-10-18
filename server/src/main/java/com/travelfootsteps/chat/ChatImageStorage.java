package com.travelfootsteps.chat;

/**
 * 채팅 사진 파일 저장소 (Plan D Task 6).
 *
 * <p>인터페이스로 두는 이유: 지금은 서버 디스크({@link LocalDiskChatImageStorage})에 두지만, 나중에 클라우드 저장소로
 * 옮겨도 {@link MessageService}는 바뀌지 않게 하려는 것이다(TokenVerifier를 인터페이스 뒤에 둔 것과 같은 원칙).
 * Firebase Storage를 쓰지 않는 이유는 Plan D "설계 결정 기록" 참고 — 무료 요금제로는 새 버킷을 만들 수 없다.
 *
 * <p>경로는 저장소 안의 상대 경로이고, 이름은 저장소가 정한다(사용자가 보낸 파일 이름은 쓰지 않는다).
 */
public interface ChatImageStorage {

    /** 저장하고 상대 경로를 돌려준다. */
    String save(byte[] bytes, ChatImageFormat format);

    byte[] load(String path);

    /** 없으면 아무것도 하지 않는다. */
    void delete(String path);
}
