CREATE TABLE trip (
    id                          BIGSERIAL PRIMARY KEY,
    firebase_uid                VARCHAR(128) NOT NULL,
    country_id                  BIGINT NOT NULL REFERENCES country(id),
    depart_date                 DATE NOT NULL,
    return_date                 DATE NOT NULL,
    passport_expiry             DATE NOT NULL,
    -- 아래 7개 컬럼은 "판정 스냅샷"이다 (2026-09-12 리뷰로 추가). POST /api/trips 시점에
    -- VisaJudgementService.judge()를 딱 한 번 호출한 결과를 그대로 굳혀서 저장하고, 이후
    -- GET에서는 절대 재계산하지 않는다 — 원본 visa_requirement가 나중에 바뀌어도 이미 만든
    -- trip_task(와 앱이 그걸 보고 예약한 로컬 알람)가 조용히 어긋나지 않게 하려는 목적이다.
    -- verdict/stay_days/passport_ok는 judge()가 항상 값을 채우므로 NOT NULL이고, 나머지
    -- 3개는 VisaJudgement 자체가 null을 허용하는 필드라 여기서도 NULL을 허용한다.
    verdict                     VARCHAR(30) NOT NULL,
    stay_days                   INTEGER NOT NULL,
    visa_free_days              INTEGER,
    passport_ok                 BOOLEAN NOT NULL,
    passport_validity_months    INTEGER,
    passport_shortfall_days     INTEGER,
    -- 스냅샷을 만들 때 사용한 visa_requirement 행의 source_fetched_at을 그대로 복사해 둔다.
    -- GET이 이 값과 "그 나라의 현재" source_fetched_at을 비교해서 다르면 judgementStale=true를
    -- 내려준다. 아직 그 나라의 visa_requirement가 아예 수집되지 않은 상태(UNVERIFIED)로 여행을
    -- 만들었을 수도 있으므로 NULL을 허용한다.
    requirement_updated_at      TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT trip_date_check CHECK (return_date >= depart_date)
);

CREATE INDEX idx_trip_firebase_uid ON trip (firebase_uid);

CREATE TABLE trip_task (
    id              BIGSERIAL PRIMARY KEY,
    trip_id         BIGINT NOT NULL REFERENCES trip(id) ON DELETE CASCADE,
    title           VARCHAR(100) NOT NULL,
    due_date        DATE NOT NULL,
    done            BOOLEAN NOT NULL DEFAULT false,
    -- 스펙 §7에 정의된 컬럼이지만 이 API 계약(Global Constraints 표)에는 노출하지 않는다 —
    -- 로컬 알람 ID는 앱(Plan B)이 기기에서 스케줄링한 값이라 서버가 알 필요가 없다. 스펙과의
    -- 일관성을 위해 컬럼만 남겨 두고 이번 API에서는 읽지도 쓰지도 않는다.
    notification_id INTEGER
);

CREATE INDEX idx_trip_task_trip ON trip_task (trip_id);
