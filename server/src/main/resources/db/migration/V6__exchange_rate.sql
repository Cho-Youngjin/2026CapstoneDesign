-- 환율 캐시 테이블. 한국수출입은행 고시환율 API를 매일 배치로 조회해 최신값만 덮어쓴다
-- (Task 9). 환율 이력은 필요하지 않으므로(스펙 §6-⑦은 "오늘 기준 환율 조회"만 요구) 통화코드당
-- 딱 한 행만 유지하는 UPSERT 캐시로 설계했다 — 이력 테이블이 아니다.
CREATE TABLE exchange_rate (
    id            BIGSERIAL PRIMARY KEY,
    currency_code CHAR(3) NOT NULL UNIQUE,
    krw_rate      NUMERIC(12, 4) NOT NULL,
    base_date     DATE NOT NULL
);
