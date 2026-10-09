# 지갑(여행 가계부) · 환율 배너 · 환율 알림 설계

- 작성일: 2026-10-09
- 담당: 조영진(팀장)
- 관련 문서: `2026-09-06-overseas-travel-app-design.md` §6-⑦, `plans/2026-09-07-plan-b-visa-checklist-wallet.md` Task 7~8
- 상태: 승인됨 (브레인스토밍 결정 사항 반영)

## 1. 목표

여행자가 나라별로 쓴 돈과 환전한 돈을 기록하고, 그 돈이 지금 원화로 얼마인지 확인하며, 환전하기 좋은 시점을 알림으로 받는다.

1. **지갑**: 식비·숙박·교통·관광·기타(여행자보험·eSIM 등) 카테고리로 지출을 기록한다.
2. **환율 배너**: 지갑 상단에 오늘 환율과 전 영업일 대비 등락(원·%)을 보여준다.
3. **환전 기록**: 환전한 현지 금액을 기록하면 현재 환율로 원화 가치를 계속 갱신해 보여준다.
4. **알림**: 전 영업일 대비 등락 알림, 목표 환율 도달 알림. 목표 설정은 지갑이 아닌 준비물 탭의 `환전` 항목에서 한다.

## 2. 결정 사항

| 주제 | 결정 | 근거 |
|---|---|---|
| 환율 소스 | 한국수출입은행(기본) + `open.er-api.com`(Exim 미지원 통화 보완) | Exim은 우리 17개 통화 중 CNY·CZK·PHP·TRY·TWD·VND를 지원하지 않는다(2026-10-08 실측). 두 소스 모두 무료이고 하루 1회 갱신된다 |
| 갱신 주기 | 값 자체는 하루 1회. 앱은 3시간마다 다시 조회해 새 값이 나오면 반영 | 시간 단위로 바뀌는 무료 소스가 없다 |
| 알림 방식 | 기기 로컬 알림(WorkManager + `flutter_local_notifications`) | FCM 대비 서버에 사용자별 상태·토큰 관리가 필요 없다 |
| 지갑 진입 | 준비물 탭 상단 세 번째 카드(기존 `보조배터리`)를 `지갑`으로 교체 | 하단 탭 6개를 유지한다. 환전 준비 → 환전 기록 → 지출 기록이 한 흐름이 된다 |
| 보조배터리 | 체크리스트 `POWER` 섹션의 행으로 이동 | 사용자 지시 |
| 지갑 단위 | 나라별(준비물 탭에서 고른 나라 = 지갑, 통화는 그 나라 `currency_code`) | 준비물 탭이 trip이 아니라 국가 기준이다 |
| 목표 설정 위치 | 준비물 탭 `MONEY`(환전) 항목의 `환율 알림 ›` → 환율 알림 화면 | 사용자 지시("지갑 페이지가 아니라 적절한 페이지") |

## 3. 범위 밖

예산 설정·초과 경고, 다인 정산, 영수증 사진/OCR, 서버 동기화(기기 변경 시 유실 감수), 환율 이력·그래프, 알림 탭 시 특정 화면으로 이동(딥링크), KRW⇄현지 환산기(Plan B Task 7의 환산기는 이번에 만들지 않는다).

## 4. 1단계 — 서버 환율 파이프라인

기존 `com.travelfootsteps.exchangerate` 패키지를 고쳐 쓴다.

### 4.1 현재 문제 (2026-10-09 확인)

- 배치가 `0 0 7 * * *`(07:00 KST)에 돈다. Exim은 영업일 11시 전후에 갱신하고 그 전에는 빈 배열을 준다. 그래서 `exchange_rate`는 지금까지 0행이다.
- 공휴일·주말 요청은 `[]`다(2026-10-09 한글날 실측).
- 통화당 최신값 한 행만 있어 전일 대비를 계산할 수 없다.
- `krw_rate NUMERIC(12,4)`라 VND(약 0.0519원)·IDR은 유효숫자가 3자리뿐이다.
- Exim의 위안화는 `CNH`(역외)이고 우리 `country`는 `CNY`라 중국은 조회되지 않는다.

### 4.2 스키마 — `V10__exchange_rate_previous.sql`

```sql
ALTER TABLE exchange_rate ALTER COLUMN krw_rate TYPE NUMERIC(18, 6);
ALTER TABLE exchange_rate ADD COLUMN previous_krw_rate  NUMERIC(18, 6);
ALTER TABLE exchange_rate ADD COLUMN previous_base_date DATE;
ALTER TABLE exchange_rate ADD COLUMN source VARCHAR(10) NOT NULL DEFAULT 'EXIM';
```

`krw_rate`는 항상 **통화 1단위당 원화**다. Exim의 `JPY(100)`·`IDR(100)`은 기존처럼 100으로 나눈다.

### 4.3 갱신 규칙 (`ExchangeRate.apply(rate, baseDate, source)`)

| 들어온 `baseDate` | 동작 |
|---|---|
| 기존보다 이후 | 기존 값을 `previous_*`로 옮기고 새 값을 현재값으로 |
| 기존과 같음 | 현재값만 교체(같은 날 재실행·정정), `previous_*` 유지 |
| 기존보다 이전 | `previous_*`가 비어 있으면 `previous_*`로 채우고, 아니면 무시 |

### 4.4 배치

- 스케줄: `0 5 11,12,15 * * *`(KST). 같은 날 여러 번 돌아도 4.3 규칙 덕분에 안전하다.
- 기동 시: `exchange_rate`가 비어 있거나 `previous_krw_rate`가 없는 행이 있으면 보정 실행을 한다.
- **Exim**: `searchdate=오늘`. `[]`이면 갱신하지 않는다. 보정 실행 시에는 오늘부터 최대 10일을 거슬러 올라가 데이터가 있는 최근 영업일 2개를 적용한다.
- **ER_API**: `GET https://open.er-api.com/v6/latest/KRW` 1회. `country.currency_code` 중 Exim 응답(정규화 코드)에 없는 통화만 저장한다. 원화 환율 = `1 / rates[code]`(소수 6자리, HALF_UP). `baseDate` = `time_last_update_unix`의 KST 날짜. `source='ER_API'`.
- 두 소스는 독립적으로 실패한다. 실패하면 로그만 남기고 기존 캐시를 유지한다(기존 정책).

### 4.5 API — `GET /api/exchange-rates/{currencyCode}`

기존 필드(`currencyCode`, `krwRate`, `baseDate`)는 유지하고 다음을 추가한다.

| 필드 | 타입 | 설명 |
|---|---|---|
| `previousKrwRate` | number \| null | 직전 고시일 환율 |
| `previousBaseDate` | date \| null | 직전 고시일 |
| `changePercent` | number \| null | `(krwRate − previous) / previous × 100`, 소수 2자리 HALF_UP |
| `source` | `"EXIM"` \| `"ER_API"` | 앱이 출처 표기를 고르는 데 쓴다 |

`SecurityConfig`: `GET /api/exchange-rates/**`는 `permitAll`이다. 백그라운드 작업에는 로그인 토큰이 없고, 공공 환율 캐시를 DB에서 읽기만 해서 외부 비용이 생기지 않는다.

### 4.6 테스트

- `ExchangeRate.apply` 3가지 분기
- 배치: Exim `[]` 무시, 100단위 통화 나눗셈, ER_API 보완 대상 선별(Exim에 있는 통화는 저장하지 않음), 한 소스 실패 시 다른 소스는 계속, 보정 실행의 거슬러 올라가기
- 컨트롤러: 새 필드와 `changePercent` 계산, 이전값이 없으면 null
- 보안: 토큰 없이 `GET /api/exchange-rates/USD` → 200, 다른 `/api/**`는 여전히 401

## 5. 2단계 — 지갑 (앱)

### 5.1 진입과 준비물 탭 변경

- `_CountryInfoRow`의 세 카드를 `플러그 · 결제 · 지갑`으로 바꾼다. `지갑` 카드는 그 나라 통화 코드를 값으로 보여주고, 누르면 `/checklist/wallet?iso=JP`로 이동한다.
- 보조배터리: `CountryDetail.powerBankWhLimit`이 있으면 `POWER` 섹션 끝에 "보조배터리 기내 반입 ({powerBankWhLimit}Wh 이하)", 예: "보조배터리 기내 반입 (100Wh 이하)" 행을 앱에서 만들어 붙인다. `POWER` 섹션이 없으면 섹션을 만든다. 값이 없으면 행을 만들지 않는다. 체크 상태는 기존 로컬 저장소에 예약 키로 저장한다.

### 5.2 화면 (`WalletPage`)

기존 디자인 토큰(`AppColors`, `AppTextStyles`)과 공용 위젯(`WireframeCard`, `PillButton`, `PillOutlineButton`, `FilterPill`, `SectionLabel`)만 쓴다. 그림자 없이 헤어라인 보더를 쓴다.

1. 헤더: "{나라} 지갑", 메뉴(⋮) → `지갑 비우기`(확인 다이얼로그)
2. 환율 배너(`infoBg`/`infoBorder`): `100엔 = 847.46원  ▲ 0.42%`, 둘째 줄 `10월 8일 고시 · 한국수출입은행`. ER_API면 `참고환율 · Rates By Exchange Rate API`. 상승은 `warn`, 하락은 `accent`. 이전값이 없으면 등락을 생략한다. 환율이 없으면 "환율 정보 없음".
3. 남은 돈 카드: `잔액 = 환전 합계 − 지출 합계`(현지), `≈ 원화`(현재 환율). 둘째 줄 `환전 ¥50,000 · 지출 ¥17,600`. 낸 원화가 입력된 환전이 있으면 평가손익(현재 원화 가치 − 낸 원화)을 덧붙인다.
4. 카테고리 필터: `전체 · 식비 · 숙박 · 교통 · 관광 · 기타`(각 합계 표시)
5. 날짜별 기록 목록: 지출(카테고리, 메모, 현지 금액, ≈원화)과 환전(`+` 금액, 메모)
6. 하단 버튼: `지출 기록`(PillButton), `환전 기록`(PillOutlineButton) → 바텀시트 폼
7. 행을 누르면 수정, 길게 누르면 삭제(확인)

### 5.3 기록과 원화 환산 규칙

| 종류 | 필드 | 원화 표시 |
|---|---|---|
| 지출 | 카테고리, 현지 금액, 메모, 날짜 | 기록 시점 환율로 **고정**(`krwPerUnitAtEntry` 저장). 기록 시 환율이 없으면 "환율 없음" |
| 환전 | 받은 현지 금액, 낸 원화(선택), 메모, 날짜 | 현재 환율로 **계속 갱신** |

카테고리 코드: `FOOD`(식비), `LODGING`(숙박), `TRANSPORT`(교통), `SIGHTSEEING`(관광, 입장료 등), `OTHER`(기타, 힌트 "여행자보험, eSIM 등").

### 5.4 데이터

- 별도 drift DB `wallet.sqlite`(`WalletDatabase`)를 쓴다. 발걸음의 `AppDatabase`(스키마 v2, 백그라운드 공유)는 건드리지 않는다.
- `Expenses(id, isoAlpha2, currencyCode, category, amountMinor INT, krwPerUnitAtEntry REAL NULL, memo, spentOn DATE)`
- `Exchanges(id, isoAlpha2, currencyCode, amountMinor INT, krwPaid INT NULL, memo, exchangedOn DATE)`
- 금액은 **통화 최소단위 정수**로 저장한다. 소수 자릿수는 JPY·VND·IDR·KRW 0, 그 외 ISO 4217 기준(대부분 2)이다. 통화별 기호·한글 단위명과 함께 `CurrencyInfo` 표 하나로 관리한다.
- 표시 단위: `{1, 100, 1000}` 중 `단위 × 1단위 환율 ≥ 10원`을 만족하는 가장 작은 값. 예: USD 1달러, JPY 100엔, VND 1,000동.

### 5.5 환율 캐시

- `shared_preferences`의 `rateCache.<CUR>`에 마지막 응답과 받은 시각을 저장한다.
- 지갑을 열면 캐시를 먼저 그리고 네트워크로 갱신한다. 당겨서 새로고침을 지원한다.
- 해외에서 데이터가 끊겨도 마지막 값과 고시일을 보여준다.

### 5.6 테스트

- `WalletRepository`(인메모리 drift): 추가·수정·삭제, 나라별 분리, 카테고리 합계, 잔액, 지갑 비우기
- `CurrencyInfo`·금액 변환·포맷, 표시 단위 선택
- `WalletPage` 위젯: 가짜 환율로 배너·잔액·필터·등락 색, 환율 없음 상태
- 준비물 탭: `지갑` 카드 이동, 보조배터리 행 생성/생략

## 6. 3단계 — 환율 알림 (앱)

### 6.1 설정 UI — `RateAlertPage` (`/checklist/rate-alert?iso=JP`)

- 진입: 준비물 체크리스트의 `MONEY` 섹션 항목에 `환율 알림 ›` 링크
- 현재 환율·등락(지갑 배너와 같은 위젯 재사용)
- `매일 등락 알림` 스위치
- 목표 환율 목록과 추가 폼: 표시 단위 기준 금액(예: "100엔당 845원") + `이하로 내려가면`(기본) / `이상으로 오르면`. 도달한 목표는 회색으로 보이고, 다시 켜거나 삭제할 수 있다
- 저장 시 이미 조건을 만족하면 "현재 환율이 이미 목표에 도달했어요"를 바로 보여준다

### 6.2 저장 (`shared_preferences`, 키 `rateAlerts.v1`)

통화별 `{ daily: bool, lastDailyBaseDate: date?, targets: [{ id, krwPerUnit, direction: BELOW|ABOVE, active, createdAt, firedAt? }] }`. 목표 금액은 표시 단위로 입력받아 1단위 기준으로 바꿔 저장한다.

### 6.3 백그라운드 작업

- 작업 이름은 `rateAlert`, 3시간 주기, 네트워크 연결 조건이다.
- 알림이 하나라도 켜지면 등록하고, 하나도 없으면 취소한다.
- 실행 순서: 설정 읽기 → 감시 통화마다 `GET /api/exchange-rates/{code}` → 환율 캐시 갱신(지갑의 "몇 시간마다" 갱신) → `RateAlertEvaluator` → 알림 발송 → 갱신된 설정 저장.

### 6.4 판단 로직 — `RateAlertEvaluator` (순수 함수)

| 알림 | 조건 | 이후 |
|---|---|---|
| 전일 대비 | `daily` 켜짐 ∧ `baseDate ≠ lastDailyBaseDate` ∧ 이전값 있음 | `lastDailyBaseDate = baseDate` |
| 목표 도달 | `active` ∧ (BELOW: 환율 ≤ 목표, ABOVE: 환율 ≥ 목표) | `active = false`, `firedAt` 기록 |

문구 예시: "엔화 100엔 847.46원 · 전 영업일보다 ▲3.57원(0.42%)", "목표 환율 도달 · 100엔 845.00원 (목표 850원 이하)".

### 6.5 알림 발송과 권한

- `RateNotifier` 인터페이스 뒤에 `flutter_local_notifications` 구현을 둔다(채널 `rate_alerts`). 알림을 누르면 앱이 열린다.
- `POST_NOTIFICATIONS`를 매니페스트에 추가하고, 처음 알림을 켤 때 `permission_handler`로 요청한다. 거부되면 스위치를 되돌리고 안내한다.

### 6.6 공용 WorkManager 디스패처

- `core/background/app_callback_dispatcher.dart`에 하나의 `callbackDispatcher`를 두고 작업 이름으로 발걸음/환율 핸들러를 나눈다.
- 발걸음 쪽 `footstep_workmanager.dart`는 등록하는 디스패처만 공용 디스패처로 바꾼다. 발걸음 로직은 손대지 않는다.

### 6.7 테스트

- `RateAlertEvaluator`: 중복 방지, 이하/이상 경계값(같을 때 발송), 이전값 없음, 비활성 목표 무시, 여러 목표 동시 충족
- `RateAlertStore`: 직렬화 왕복, 표시 단위 → 1단위 변환
- 작업 핸들러: 가짜 API·가짜 알림기로 캐시 갱신과 발송 확인, API 실패 시 설정 불변
- 디스패처: 작업 이름별 분기, 모르는 이름은 `true`
- `RateAlertPage` 위젯: 목표 추가, 이미 도달 경고, 권한 거부 시 스위치 원복

## 7. 기존 문서와의 차이

- 스펙 §6-⑦의 "환전 알림: FCM, D-14 이내 매일"은 이 문서의 로컬 알림(등락·목표)으로 대체한다.
- 스펙 §6-⑦·Plan B Task 8의 지갑 카테고리(식비/교통/숙박/쇼핑/기타)는 식비/숙박/교통/관광/기타로 바꾸고, 여행별이 아니라 나라별로 묶는다. 환전 기록을 새로 둔다.
- Plan B Task 7~8은 이 설계로 대체되며 새 구현 계획서를 따른다.

## 8. 위험과 한계

- 제조사 절전 정책으로 알림이 몇 시간 늦을 수 있다. 고시 환율이 하루 1회 바뀌므로 감수한다.
- ER_API 값은 은행 고시환율이 아닌 참고환율이다. 화면에 출처를 표기한다.
- 지갑 데이터는 기기에만 있어 앱 삭제·기기 변경 시 사라진다(스펙의 기존 결정).
- 같은 나라를 다시 여행하면 기록이 이어진다. 날짜로 구분하거나 `지갑 비우기`를 쓴다.
