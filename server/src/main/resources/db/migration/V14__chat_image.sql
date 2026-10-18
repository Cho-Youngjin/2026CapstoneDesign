-- 채팅 사진 (Plan D Task 6). 사진 파일은 DB가 아니라 서버 디스크(chat.image-dir)에 두고,
-- 여기에는 그 디렉터리 안의 상대 경로(서버가 만든 "UUID.확장자")만 적는다. 이 값은 앱에 그대로 내보내지 않는다 —
-- 앱은 /api/rooms/{roomId}/images/{messageId}로 받고, 서버가 멤버인지 확인한 뒤 파일을 읽어 준다.
ALTER TABLE chat_message ADD COLUMN image_path VARCHAR(300);

-- 사진 메시지는 파일 경로가 꼭 있어야 하고, 글자 메시지는 글자가 꼭 있어야 한다.
ALTER TABLE chat_message ADD CONSTRAINT chat_message_content_check
    CHECK ((type = 'IMAGE' AND image_path IS NOT NULL) OR (type = 'TEXT' AND text IS NOT NULL));

-- 앱이 사진마다 붙이는 업로드 id. 서버는 저장했는데 응답이 끊겨 앱이 [다시 시도]하면 같은 id가 다시 온다 —
-- 그때 새로 저장하지 않고 처음 메시지를 돌려주려고 둔다. 같은 방·같은 사람 안에서만 겹치지 않으면 된다.
-- 값이 없는 행(글자 메시지, id 없이 올린 사진)은 제약에서 뺀다(부분 인덱스).
ALTER TABLE chat_message ADD COLUMN client_id VARCHAR(64);
CREATE UNIQUE INDEX uq_chat_message_client_id ON chat_message (room_id, sender_uid, client_id)
    WHERE client_id IS NOT NULL;
