-- trip_checklist: 여행 한 건에 귀속된 준비물 체크리스트다 (2026-09-12 리뷰로 추가).
-- V5__checklist_template.sql의 checklist_template 테이블을 매번 라이브로 조인해서 보여주지
-- 않고, 여행 생성 시점(TripController.create())에 그 나라 전용 + 공통(country_id IS NULL)
-- 템플릿을 전부 복사해 이 테이블에 스냅샷으로 굳힌다. 이유는 trip 테이블의 판정 스냅샷
-- (V4__trip.sql 상단 주석)과 완전히 같다 — 이후 관리자가 공통 템플릿 문구를 고치거나 국가별
-- 항목을 추가/삭제해도, 이미 여행을 만들어 체크까지 진행 중인 사용자의 목록이 조용히 바뀌거나
-- 항목이 사라지면 안 되기 때문이다. 대신 이 스냅샷은 그 자체가 사용자별 상태(checked)를
-- 가지므로 판정 스냅샷과 달리 "다시 계산해서 갈아엎는" 새로고침 대상이 아니다.
--
-- V7은 이 계획서의 다른 태스크(Task 11의 footsteps 기능)가 이미 예약해 두었으므로, 이 마이그
-- 레이션은 V6를 건너뛰고 V8 번호를 쓴다(같은 계획 문서에서 태스크별로 마이그레이션 번호를
-- 미리 배정해 둔 결과이며, 이 브랜치에 아직 V6/V7 파일이 없는 것은 해당 태스크가 아직 이
-- 브랜치에 병합되지 않았기 때문이다).
CREATE TABLE trip_checklist (
    id          BIGSERIAL PRIMARY KEY,
    trip_id     BIGINT NOT NULL REFERENCES trip(id) ON DELETE CASCADE,
    category    VARCHAR(30) NOT NULL,
    title       VARCHAR(100) NOT NULL,
    description VARCHAR(255),
    priority    INTEGER NOT NULL DEFAULT 0,
    checked     BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX idx_trip_checklist_trip ON trip_checklist (trip_id);
