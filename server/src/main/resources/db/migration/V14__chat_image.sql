-- 채팅 사진 (Plan D Task 6). 사진 파일은 DB가 아니라 서버 디스크(chat.image-dir)에 두고,
-- 여기에는 그 디렉터리 안의 상대 경로(서버가 만든 "UUID.확장자")만 적는다. 이 값은 앱에 그대로 내보내지 않는다 —
-- 앱은 /api/rooms/{roomId}/images/{messageId}로 받고, 서버가 멤버인지 확인한 뒤 파일을 읽어 준다.
ALTER TABLE chat_message ADD COLUMN image_path VARCHAR(300);

-- 사진 메시지는 파일 경로가 꼭 있어야 하고, 글자 메시지는 글자가 꼭 있어야 한다.
ALTER TABLE chat_message ADD CONSTRAINT chat_message_content_check
    CHECK ((type = 'IMAGE' AND image_path IS NOT NULL) OR (type = 'TEXT' AND text IS NOT NULL));
