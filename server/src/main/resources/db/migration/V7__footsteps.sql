CREATE TABLE checkin (
    id            BIGSERIAL PRIMARY KEY,
    firebase_uid  VARCHAR(128) NOT NULL,
    lat           DOUBLE PRECISION NOT NULL,
    lng           DOUBLE PRECISION NOT NULL,
    country_id    BIGINT NOT NULL REFERENCES country(id),
    recorded_at   TIMESTAMPTZ NOT NULL,
    source        VARCHAR(10) NOT NULL,
    -- 재전송으로 인한 중복 체크인 방지 (2026-09-12 리뷰 반영) — local_id는 기기별 로컬 정수라
    -- 전역 dedup 키로 못 쓰므로, 실제 발생 시각을 키로 쓴다.
    UNIQUE (firebase_uid, recorded_at)
);

CREATE INDEX idx_checkin_firebase_uid ON checkin(firebase_uid);

CREATE TABLE daily_steps (
    id            BIGSERIAL PRIMARY KEY,
    firebase_uid  VARCHAR(128) NOT NULL,
    date          DATE NOT NULL,
    country_id    BIGINT NOT NULL REFERENCES country(id),
    step_count    INTEGER NOT NULL,
    UNIQUE (firebase_uid, date, country_id)
);
