-- 공통 준비물 보강 (country_id NULL = 모든 국가 공통).
-- 출처: 국토교통부 보도자료(2026-04-08), 인천공항 제한물품, 관세청 여행자 휴대품 통관,
--       대한항공 리콜 보조배터리 공지, 외교부 해외안전여행. 이미 실행된 V5는 고치지 않고 여기서 UPDATE/INSERT 한다.
-- 주의: 체크리스트는 여행 생성 시점에 복사되므로, 이 변경은 이후 새로 만든 여행부터 보인다.

-- 1) 기존 공통 항목 문구 보강
UPDATE checklist_template
SET title = '보조배터리 확인 (1인 2개)',
    description = '1인 최대 2개. 100Wh 이하 가능, 100~160Wh는 항공사 승인 필요, 160Wh 초과 불가. 위탁·선반 보관·기내 충전 금지'
WHERE country_id IS NULL AND category = 'POWER' AND title = '보조배터리 용량 확인';

-- 2) 새 공통 항목
INSERT INTO checklist_template (country_id, category, title, description, priority) VALUES
(NULL, 'POWER',    '리콜 보조배터리 확인',          '리콜 제품은 기내·위탁 모두 반입 금지', 25),
(NULL, 'DOCUMENT', '귀국 면세 범위 확인',           '800달러·주류 2L(400달러)·담배 200개비·향수 100ml 이하. 초과는 자진신고', 85),
(NULL, 'DOCUMENT', '귀국 시 식품·동식물 신고',      '육류·과일·채소류는 신고 대상', 86),
(NULL, 'MONEY',    '외화 1만 달러 초과 신고',       '미화 1만 달러 초과는 세관 신고', 87),
(NULL, 'DOCUMENT', '영사콜센터 번호 저장',          '+82-2-3210-0404 (24시간, 유료)', 88),
(NULL, 'DOCUMENT', '기내 액체류 확인',             '100ml 이하 용기를 1L 지퍼백 1개에. 큰 용량은 위탁', 89);
