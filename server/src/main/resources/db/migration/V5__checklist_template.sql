CREATE TABLE checklist_template (
    id          BIGSERIAL PRIMARY KEY,
    country_id  BIGINT REFERENCES country(id),
    category    VARCHAR(30) NOT NULL,
    title       VARCHAR(100) NOT NULL,
    description VARCHAR(255),
    priority    INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_checklist_template_country ON checklist_template (country_id);

-- country_id가 NULL인 행은 모든 국가에 공통으로 적용되는 템플릿이다.
INSERT INTO checklist_template (country_id, category, title, description, priority) VALUES
(NULL, 'POWER',     '플러그 어댑터 준비',       '목적지 플러그 타입에 맞는 어댑터를 준비한다', 10),
(NULL, 'POWER',     '보조배터리 용량 확인',      '항공 반입 규정(Wh 제한)을 확인한다', 20),
(NULL, 'PAYMENT',   '해외 결제 카드 준비',       '해외 결제 가능한 카드를 준비하거나 현금을 환전한다', 30),
(NULL, 'SIM',       '유심/eSIM 준비',           '현지 유심 또는 eSIM을 사전에 준비한다', 40),
(NULL, 'CLOTHING',  '계절 의류 확인',           '목적지 계절에 맞는 의류를 준비한다', 50),
(NULL, 'DOCUMENT',  '여행자보험 가입',          '여행 기간에 맞는 여행자보험에 가입한다', 60),
(NULL, 'DOCUMENT',  '왕복 항공권·숙소 확정',     '입국 심사 시 요구될 수 있다', 70),
(NULL, 'MONEY',     '환전',                    '목적지 통화로 환전한다', 80);
