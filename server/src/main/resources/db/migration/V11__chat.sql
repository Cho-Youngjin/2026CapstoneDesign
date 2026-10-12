-- 그룹 채팅 (Plan D, 2026-10-08 개정 — Firestore 대신 PostgreSQL에 채팅을 둔다).
-- Task 1(그룹·프로필)과 Task 2(메시지)가 함께 쓰는 기본 테이블 네 개를 만든다.
-- DM 중복 방지용 dm_key는 V12, 사진 경로 image_path는 V13에서 각 Task가 추가한다.
-- (원래 V10으로 만들었으나 환율 작업의 V10__exchange_rate_previous.sql이 먼저 master에 들어가 V11로 옮겼다.)
--
-- 다른 테이블(trip 등)과 마찬가지로 사용자 테이블에 FK를 걸지 않고 firebase_uid 문자열로만
-- 사람을 가리킨다. 사용자의 원본은 Firebase Auth이고, app_user는 화면 표시용 프로필 캐시일
-- 뿐이라 행이 없을 수도 있다(로그인 후 프로필 업로드 전, 또는 업로드 실패).

-- 화면에 이름·사진을 띄우기 위한 프로필. 서버의 TokenVerifier는 uid만 알려주므로,
-- 앱이 로그인 직후 PUT /api/me/profile로 올린다. fcm_token은 푸시 알림(Task 8)용으로
-- 미리 만들어 둔다 — 컬럼 하나 때문에 나중에 마이그레이션을 늘리지 않으려는 것이다.
CREATE TABLE app_user (
    firebase_uid  VARCHAR(128) PRIMARY KEY,
    display_name  VARCHAR(100),
    photo_url     VARCHAR(500),
    fcm_token     VARCHAR(500),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 채팅방. GROUP(초대 코드로 모이는 여행 그룹)과 DM(같은 그룹 멤버 둘)이 한 테이블을 쓴다 —
-- 메시지·멤버·읽음 처리가 완전히 같아서 나누면 같은 코드를 두 벌 쓰게 된다.
CREATE TABLE chat_room (
    id                    BIGSERIAL PRIMARY KEY,
    type                  VARCHAR(10) NOT NULL,
    -- GROUP만 이름과 초대 코드를 가진다. DM의 이름은 앱이 상대 프로필로 표시한다.
    name                  VARCHAR(50),
    -- 6자리 고정이지만 CHAR(6)가 아니라 VARCHAR(6)로 둔다: CHAR는 Hibernate의 스키마 검증
    -- (ddl-auto: validate)에서 String 필드와 타입이 다르다고 판정돼 columnDefinition을 따로
    -- 적어야 하고, 길이 보장은 아래 CHECK가 대신한다.
    invite_code           VARCHAR(6) UNIQUE,
    -- 아래 세 컬럼은 방 목록 정렬·미리보기용 비정규화다. 목록을 그릴 때마다 방별 최신 메시지를
    -- 조회하지 않으려고 메시지 저장 시점(MessageService)에 함께 갱신한다.
    -- last_message_id에는 FK를 걸지 않는다: chat_message가 chat_room을 참조하므로 순환 참조가 되고,
    -- 이 값은 화면 표시용 힌트라 어긋나도 데이터가 망가지지 않는다.
    last_message_id       BIGINT,
    last_message_preview  VARCHAR(100),
    last_message_at       TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chat_room_type_check CHECK (type IN ('GROUP', 'DM')),
    CONSTRAINT chat_room_group_fields_check
        CHECK (type <> 'GROUP' OR (name IS NOT NULL AND invite_code IS NOT NULL)),
    CONSTRAINT chat_room_invite_code_length_check
        CHECK (invite_code IS NULL OR char_length(invite_code) = 6)
);

-- 방 멤버. 읽음 상태(last_read_message_id)를 메시지 쪽이 아니라 여기 둔다: 메시지마다
-- "누가 읽었는지"를 쓰면 멤버 수 × 메시지 수만큼 쓰기가 생기지만, 이렇게 하면 사람당
-- "어디까지 읽었는지" 한 값만 갱신하면 된다(스펙 §6-④). 안 읽은 개수는
-- "내 last_read_message_id보다 id가 큰, 남이 보낸 메시지 수"로 센다.
CREATE TABLE chat_room_member (
    room_id               BIGINT NOT NULL REFERENCES chat_room(id) ON DELETE CASCADE,
    firebase_uid          VARCHAR(128) NOT NULL,
    joined_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- null = 아직 아무 메시지도 읽지 않음 (Task 7에서 사용)
    last_read_message_id  BIGINT,
    PRIMARY KEY (room_id, firebase_uid)
);

-- PK가 (room_id, firebase_uid) 순서라 "이 방의 멤버들"은 PK 인덱스로 찾지만,
-- "내가 속한 방들"(GET /api/rooms)은 firebase_uid로 시작하는 인덱스가 따로 필요하다.
CREATE INDEX idx_chat_room_member_uid ON chat_room_member (firebase_uid);

-- 메시지. 위치 공유 메시지(1회성 핀)는 이번 범위에서 빠졌으므로(Plan D 제외 범위) type은
-- TEXT와 IMAGE만 허용한다. IMAGE에 필요한 image_path 컬럼은 V13에서 추가한다.
CREATE TABLE chat_message (
    id          BIGSERIAL PRIMARY KEY,
    room_id     BIGINT NOT NULL REFERENCES chat_room(id) ON DELETE CASCADE,
    sender_uid  VARCHAR(128) NOT NULL,
    type        VARCHAR(10) NOT NULL,
    text        VARCHAR(1000),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chat_message_type_check CHECK (type IN ('TEXT', 'IMAGE'))
);

-- 채팅방 화면은 "이 방의 최신 메시지 30개", 위로 스크롤하면 "이 id보다 오래된 30개"를 읽는다.
-- 둘 다 room_id로 거르고 id 내림차순으로 자르는 조회라 이 복합 인덱스 하나로 처리된다.
CREATE INDEX idx_chat_message_room_id_desc ON chat_message (room_id, id DESC);
