-- 지갑·환율 알림 설계 §4.2. 전 영업일 대비 등락을 계산하려면 "직전 고시일" 값이 필요하다.
-- 이력 테이블을 만들지 않고 직전 값 한 칸(previous_*)만 둔다 — 화면과 알림이 쓰는 건 "오늘 vs 직전 영업일" 뿐이다.
-- krw_rate의 소수 자릿수를 4 → 6으로 넓히는 이유: VND(약 0.0519원)·IDR처럼 1단위 환율이 아주 작은
-- 통화는 4자리면 유효숫자가 3자리뿐이라 하루 등락 %가 거칠게 나온다.
-- source: 값의 출처. EXIM(한국수출입은행 고시환율) 또는 ER_API(open.er-api.com 참고환율).
ALTER TABLE exchange_rate ALTER COLUMN krw_rate TYPE NUMERIC(18, 6);
ALTER TABLE exchange_rate ADD COLUMN previous_krw_rate  NUMERIC(18, 6);
ALTER TABLE exchange_rate ADD COLUMN previous_base_date DATE;
ALTER TABLE exchange_rate ADD COLUMN source VARCHAR(10) NOT NULL DEFAULT 'EXIM';
