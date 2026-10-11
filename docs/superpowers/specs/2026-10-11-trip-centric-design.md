# 여행계획 중심 재구성 설계

- 작성일: 2026-10-11
- 브랜치: `trip-list`
- 관련 문서: `2026-09-06-overseas-travel-app-design.md`(메인 설계), `2026-10-09-wallet-exchange-alerts-design.md`(지갑·환율 알림), Plan B(`plans/2026-09-07-plan-b-visa-checklist-wallet.md`)
- 후속 작업(별도 스펙): Firebase 이메일/비밀번호 회원가입·로그인 — 메인 설계 §114의 확장 방식 그대로, 서버 변경 없음

## 1. 배경 — 지금 무엇이 문제인가

| 증상 | 원인 |
|---|---|
| 앱을 껐다 켜면 여행계획이 초기화된 것처럼 보인다 | 여행은 서버 `trip` 테이블에 uid별로 이미 저장된다. 하지만 비자 탭이 항상 빈 입력 폼으로 시작하고, 앱은 "활성 여행 id" 하나만 기억한다. 여행 목록 API(`GET /api/trips`)도 없다 |
| 판정 후 [준비물 체크리스트]를 누르면 베트남이 나온다 | `ChecklistPage`가 `_isoAlpha2 = 'VN'`으로 시작하고, 여행과 무관하게 국가 공통 템플릿(`GET /api/countries/{iso}/checklist`) + 기기 로컬 체크 상태를 쓴다. 서버에는 여행별 체크리스트(`trip_checklist`, `GET/POST /api/trips/{id}/checklist…`)가 이미 있지만 앱이 쓰지 않는다 |
| 같은 나라를 두 번 가면 가계부가 섞인다 | 지갑 DB(`wallet.sqlite`)가 `isoAlpha2`로 기록을 묶는다 |

## 2. 목표

여행 한 건이 앱의 중심 단위가 된다. 여행마다 판정·준비 일정·체크리스트·가계부가 따로 있고, 지난 여행도 그대로 다시 볼 수 있다.

범위 밖: 여행 수정(날짜 변경 — 새로 만들면 된다), 체크리스트 오프라인 캐시/체크 대기열, "직접 추가" 행(지금도 동작 없는 자리표시), 지갑 서버 동기화.

## 3. 화면 구조와 흐름

### 3.1 여행 탭 (`/visa`, 탭 라벨 '비자' → '여행')

- 첫 화면은 **내 여행 목록**이다.
  - **다가오는 여행**: `returnDate >= 오늘`, 출발일 오름차순.
  - **지난 여행**: `returnDate < 오늘`, 출발일 내림차순.
  - 카드: 국가명, 날짜(`M/d~M/d`), 판정 배지(무비자 / 무비자 초과 / 비자 필요 / 확인 필요 — 기존 `visa_result_display.dart` 표현 재사용).
  - 카드를 누르면 여행 상세(`/visa/trip/:id`)로 간다.
- 상단 [+ 새 여행계획 만들기] → 기존 입력 폼(`/visa/new`).
- 판정을 받으면 `pushReplacement`로 새 여행의 상세 화면으로 간다 — 뒤로 가기는 폼이 아니라 목록으로 돌아간다.
- 여행이 없으면 "첫 여행계획을 만들어 보세요" + 만들기 버튼.

### 3.2 여행 상세 (`/visa/trip/:id`)

- 지금의 `VisaResultPage` 내용(판정 배지·근거·준비 일정·판정 기준 변경 배너)을 그대로 쓰되, `activeTripProvider` 대신 라우트의 `id`로 여행을 조회한다.
- 하단 버튼 2개:
  - **[준비물 체크리스트]** — 이 여행을 선택된 여행으로 저장하고 `context.go(AppRoutes.checklist)`.
  - **[지갑]** — `AppRoutes.walletOf(tripId, iso)`로 push.
- 상단 메뉴 **[여행 삭제]** — 확인 다이얼로그 → 서버 삭제 성공 시 앱 쪽 정리(§4.3) → 목록으로.

### 3.3 준비물 탭 (`/checklist`)

- 상단: 국가명 · 날짜 + [여행 바꾸기] → 내 여행 목록 바텀시트(다가오는/지난 구분 동일). 국가 직접 선택과 VN 기본값은 없앤다.
- 보여줄 여행(`resolveSelectedTrip`, 순수 함수):
  1. 저장된 선택 여행 id가 목록에 있으면 그 여행
  2. 없으면 가장 가까운 다가오는 여행(출발일 오름차순 첫 번째)
  3. 없으면 가장 최근 지난 여행(출발일 내림차순 첫 번째)
  4. 여행이 하나도 없으면 null → "여행계획을 먼저 만들어 주세요" + [여행계획 만들기](`/visa/new`)
- 체크리스트는 그 여행의 서버 체크리스트(`trip_checklist`)다. 체크 상태도 서버에 여행별로 남는다.
- 국가 정보 줄(결제 등급 등)과 지갑 버튼, 환전 섹션의 환율 알림 링크는 선택된 여행의 나라 기준이다. 지갑 버튼은 그 여행의 가계부로 간다. 환율 알림은 통화 단위 설정이므로 기존 그대로다.

### 3.4 지갑 (`/checklist/wallet?trip=<id>&iso=XX`)

화면은 그대로이고 기록의 묶음 기준만 나라 → 여행으로 바뀐다. 통화는 `iso`로 정한다(기존 `currencyInfoOf`).

## 4. 데이터

### 4.1 서버 (스키마 변경 없음)

- `GET /api/trips` — 로그인 사용자 uid의 여행 요약 목록. 출발일 내림차순.
  ```json
  [{"id": 3, "countryIso2": "JP", "countryNameKo": "일본",
    "departDate": "2026-11-03", "returnDate": "2026-11-08", "verdict": "VISA_FREE_OK"}]
  ```
  - `TripRepository.findByFirebaseUidOrderByDepartDateDesc(uid)` 추가. 판정은 `trip`의 스냅샷 컬럼을 그대로 읽는다(재계산 없음).
  - 국가는 `countryRepository.findAllById(countryIds)`로 한 번에 조회한다(N+1 방지).
- `DELETE /api/trips/{id}` — 소유자가 아니거나 없으면 404(`findOwnedTripOrThrow` 재사용). 성공 시 204. `trip_task`·`trip_checklist`는 FK `ON DELETE CASCADE`로 같이 지워진다.
- 서버 프로덕션 코드에는 CLAUDE.md의 Spring 학습 주석 규칙을 적용한다.

### 4.2 앱

- `TripApi`에 `listTrips()`, `deleteTrip(id)`, `getChecklist(tripId)`, `checkItem(tripId, itemId, checked)` 추가. 모델 `TripSummary{id, countryIso2, countryNameKo, departDate, returnDate, verdict}`, `TripChecklistItem{id, category, title, description, priority, checked}`(카테고리 한글 라벨은 기존 `ChecklistItem.categoryLabelKo`와 같은 표를 공유).
- **여행 목록 provider** — 서버 목록을 가져오고 성공하면 SharedPreferences(`trips.cache.v1`)에 JSON으로 캐시한다. 실패하면 캐시를 `offline: true`로 돌려준다. 캐시도 없으면 오류를 그대로 낸다.
- **선택된 여행 id** — 기존 `active_trip_id` 키를 `selected_trip_id`로 바꾼 Notifier(SharedPreferences). 기존 `activeTripProvider`는 없애고, 상세 화면은 `tripProvider(id)`(family)로 조회한다.
- **체크리스트** — 서버 체크리스트를 쓰고 토글은 낙관적 업데이트(화면 먼저 반영 → 서버 저장, 실패 시 되돌림 + 스낵바). 나라별 로컬 체크 저장소 `ChecklistCheckedStore`와 관련 provider는 삭제한다.
- **보조배터리 행** — 서버 항목이 아니라 앱이 국가 정보(`powerBankWhLimit`)로 만드는 행이므로, 체크 상태만 SharedPreferences `checklist_powerbank_<tripId>`(bool)에 둔다.
- **지갑 DB(drift)** — `Expenses`·`Exchanges`의 `isoAlpha2` 컬럼을 `tripId`(int)로 바꾸고 `schemaVersion` 1 → 2. 마이그레이션은 기존 데이터를 버리고 두 테이블을 다시 만든다(테스트 데이터뿐이라 결정, 2026-10-11). `watchExpenses/watchExchanges/clearWallet`과 provider family 키도 `tripId`로 바꾼다.
- 환율 알림·환율 캐시는 통화 기준이라 변경 없음.

### 4.3 여행 삭제 시 앱 쪽 정리

서버 삭제가 성공한 뒤에만:
1. `clearWallet(tripId)`
2. `checklist_powerbank_<tripId>` 삭제
3. 선택된 여행이었다면 선택 해제
4. 여행 목록 provider invalidate(캐시도 다음 성공 조회 때 갱신)

## 5. 오류 처리

- **여행 목록**: 조회 실패 + 캐시 있음 → 캐시 표시 + "오프라인 · 마지막으로 불러온 목록" 안내. 캐시도 없음 → 오류 + [다시 시도].
- **여행 상세 404**: "여행을 찾을 수 없습니다" + 목록으로 버튼. 선택된 여행이 404였다면 선택 해제(다음에 §3.3 규칙으로 다시 고른다).
- **체크 토글 실패**: 되돌림 + "저장하지 못했습니다" 스낵바.
- **삭제 실패**: 앱 쪽은 아무것도 지우지 않고 스낵바만.
- **체크리스트 조회 실패(오프라인 등)**: 오류 + [다시 시도]. 상단 여행 정보와 지갑 버튼은 캐시된 목록으로 계속 동작한다.

## 6. 테스트

- 서버: `TripController` `@WebMvcTest` — 목록이 내 여행만 출발일 내림차순으로 나오는지, 삭제가 남의 여행이면 404·내 여행이면 204인지. Repository 쿼리는 Testcontainers(CI) 테스트.
- 앱 단위: `resolveSelectedTrip` 규칙 4가지, 여행 목록 캐시(저장/실패 시 캐시 반환/캐시 없음 오류), 지갑 DB의 tripId 조회·삭제.
- 앱 위젯: 여행 목록(다가오는/지난 분류, 빈 화면, 오프라인 안내), 상세 화면(버튼 이동, 삭제 흐름), 준비물 탭(여행 없음 안내, 여행 바꾸기 시트, 서버 체크 토글 + 실패 시 되돌림).
- 기존 visa·checklist·wallet 테스트를 새 구조에 맞게 수정.

## 7. 작업 순서

1. 서버: 목록·삭제 API
2. 앱: TripApi 확장, 목록 캐시, 선택 여행 provider
3. 여행 탭: 목록 화면, `/visa/new`, `/visa/trip/:id`, 삭제
4. 지갑: tripId 기준 DB·라우트
5. 준비물 탭: 선택 여행 기반 재구성 + 서버 체크리스트
6. 실기기 확인 → Codex 리뷰 → PR
