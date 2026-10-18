-- 1:1 DM (Plan D Task 5). DM 방은 chat_room에 type = 'DM'으로 함께 둔다 — 메시지·멤버·구독 권한을
-- 그룹과 똑같이 쓰기 위해서다.
--
-- dm_key는 두 사람의 uid를 정렬해 "작은uid|큰uid"로 이은 값이다. 누가 먼저 열든 같은 값이 나오므로
-- UNIQUE 제약 하나로 "같은 두 사람의 DM이 둘 생기는 것"을 DB가 막는다(동시에 양쪽에서 열어도).
-- uid는 최대 128자라 128 + 1 + 128 = 257자를 담을 수 있게 260으로 둔다.
ALTER TABLE chat_room ADD COLUMN dm_key VARCHAR(260) UNIQUE;

-- DM은 dm_key가 꼭 있어야 하고 초대 코드는 없어야 한다(코드로 남의 DM에 참여할 수 없게).
-- 그룹 쪽 규칙(이름·초대 코드 필수)은 V11의 chat_room_group_fields_check가 이미 지킨다.
ALTER TABLE chat_room ADD CONSTRAINT chat_room_dm_fields_check
    CHECK (type <> 'DM' OR (dm_key IS NOT NULL AND invite_code IS NULL));
