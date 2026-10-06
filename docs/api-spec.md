# API 명세서 — 해외여행 발걸음 서버 (Plan A)

> 이 문서는 `server/` 코드(컨트롤러/DTO)를 직접 읽어서 작성했다. 실제 구현과 항상 일치해야 하며, 엔드포인트를 바꾸면 이 문서도 같은 PR에서 함께 갱신한다.
>
> Base URL: 로컬 개발 `http://localhost:8080` (배포 URL 미정 — 아직 배포 전)

## 인증

`/api/health`를 제외한 모든 `/api/**` 엔드포인트는 Firebase ID 토큰이 필요하다.

```
Authorization: Bearer <Firebase ID Token>
```

- 헤더가 없거나 토큰이 유효하지 않으면 **401 Unauthorized**를 응답한다.
- 정의되지 않은 경로는 전부 **403 Forbidden**(`denyAll`)이다.
- 인증된 사용자의 식별자(Firebase `uid`)는 서버가 토큰에서 직접 꺼내 쓴다 — 클라이언트가 별도로 `uid`를 바디/쿼리에 실어 보낼 필요도, 방법도 없다.

## 공통 에러 응답

Spring Boot 기본 에러 바디 형식을 그대로 쓴다:

```json
{
  "timestamp": "2026-09-13T12:00:00.000+00:00",
  "status": 404,
  "error": "Not Found",
  "path": "/api/trips/999"
}
```

| 상태 코드 | 의미 |
|---|---|
| 400 | 요청 값 검증 실패(필수 필드 누락, 형식 오류, 알 수 없는 국가 코드 등) |
| 401 | 인증 토큰 없음/무효 |
| 404 | 리소스 없음, 또는 **다른 사용자 소유의 리소스**(소유권 없으면 403이 아니라 404로 감춘다) |
| 500 | 서버 내부 오류 |

---

## 1. Health

### `GET /api/health`
인증 불필요. 배포/모니터링용 헬스체크.

**응답 200**
```json
{ "status": "UP" }
```

---

## 2. 국가 정보 (Country)

### `GET /api/countries`
전체 국가 목록(한글 이름 오름차순).

**응답 200**
```json
[
  { "isoAlpha2": "VN", "nameKo": "베트남", "nameEn": "Vietnam", "continent": "ASIA", "tier": "A" }
]
```

### `GET /api/countries/{iso2}`
국가 상세 정보(플러그 타입, 전압, 통화 등).

**응답 200**
```json
{
  "isoAlpha2": "VN", "isoAlpha3": "VNM", "nameKo": "베트남", "nameEn": "Vietnam",
  "continent": "ASIA", "tier": "A",
  "plugTypes": "A,C", "voltageV": 220, "frequencyHz": 50,
  "currencyCode": "VND", "cardAcceptance": "MEDIUM", "powerBankWhLimit": 160
}
```
**404** — 존재하지 않는 `iso2`.

### `GET /api/countries/{iso2}/checklist`
이 국가에 적용되는 **공통 준비물 템플릿**(읽기 전용, 사용자별 체크 상태 없음). 여행 생성 전 미리보기용.

**응답 200**
```json
[
  { "id": 1, "category": "서류", "title": "여권", "description": "유효기간 6개월 이상", "priority": 1 }
]
```
> 실제로 사용자가 체크하는 화면은 여행 생성 후 `GET/POST /api/trips/{id}/checklist`를 쓴다 (아래 5절).

---

## 3. 여행경보 / 재외공관

### `GET /api/countries/{iso2}/alerts`
외교부 여행경보 목록(최신순). 배치가 미리 채운 캐시를 읽기만 한다.

**응답 200**
```json
[
  { "id": 1, "level": 2, "region": "전 지역", "title": "베트남 여행경보 2단계", "issuedAt": "2026-09-01T00:00:00+09:00" }
]
```
`level`: 1~4단계, 파싱 실패 시 **0**(UNKNOWN — "안전"으로 절대 낙관 처리하지 않는다).

**404** — 존재하지 않는 `iso2`.

### `GET /api/countries/{iso2}/embassies`
재외공관 목록.

**응답 200**
```json
[
  {
    "id": 1, "type": "대사관", "name": "주베트남 대한민국 대사관",
    "lat": 21.0, "lng": 105.8, "phone": "+84-24-...", "emergencyPhone": "+84-90-...",
    "address": "..."
  }
]
```
**404** — 존재하지 않는 `iso2`.

---

## 4. 환율

### `GET /api/exchange-rates/{currencyCode}`
한국수출입은행 고시환율 캐시 조회(일 1회 배치 갱신). `currencyCode`는 대소문자 무관(대문자로 정규화).

**응답 200**
```json
{ "currencyCode": "VND", "krwRate": 0.0546, "baseDate": "2026-09-13" }
```
**404** — 캐시에 없는 통화 코드.

---

## 5. 여행 계획 (Trip) — 비자 판정 + 역산 일정 + 준비물

> **설계 핵심: 스냅샷 + 명시적 새로고침.** `POST`가 비자 판정을 **한 번만** 계산해서 `trip`에 그대로 저장한다. 이후 `GET`은 그 저장된 값만 읽고, 원본 데이터(`visa_requirement`)가 바뀌어도 절대 재계산하지 않는다 — 대신 `judgementStale`로 "기준이 바뀌었다"는 사실만 알려주고, 실제 재계산은 사용자가 `POST /refresh`로 명시적으로 동의할 때만 일어난다. 이미 확정된 여행 일정과 로컬 알람이 조용히 어긋나는 것을 막기 위한 설계다.

### `POST /api/trips`
여행을 생성하고, 비자 판정 + 역산 준비 일정 + 준비물 체크리스트(스냅샷)를 한 번에 만든다.

**요청**
```json
{
  "countryIso2": "VN",
  "departDate": "2026-12-20",
  "returnDate": "2026-12-25",
  "passportExpiry": "2027-06-01"
}
```
| 필드 | 검증 |
|---|---|
| `countryIso2` | 필수 |
| `departDate`, `returnDate`, `passportExpiry` | 필수, `returnDate`는 `departDate`보다 앞설 수 없음(위반 시 400) |

**응답 200** — 아래 "TripResponse" 참고.
**404** — 존재하지 않는 국가.
**400** — 필수 필드 누락 / `returnDate < departDate`.

### `GET /api/trips/{id}`
저장된 스냅샷 그대로 조회.

**응답 200 (TripResponse 공통 형태 — POST/GET/refresh 동일)**
```json
{
  "id": 1,
  "countryIso2": "VN",
  "countryNameKo": "베트남",
  "departDate": "2026-12-20",
  "returnDate": "2026-12-25",
  "passportExpiry": "2027-06-01",
  "visaResult": {
    "verdict": "VISA_FREE_OK",
    "stayDays": 5,
    "visaFreeDays": 45,
    "passportOk": true,
    "passportValidityMonths": null,
    "passportShortfallDays": null
  },
  "tasks": [
    { "id": 1, "title": "여권 유효기간 확인", "dueDate": "2026-12-13", "done": false }
  ],
  "judgementStale": false
}
```

`verdict` 값 (4가지, **문자열 그대로 클라이언트-바인딩 고정값** — 임의 변경 금지):
| 값 | 의미 |
|---|---|
| `VISA_FREE_OK` | 무비자 체류일 이내 |
| `VISA_FREE_EXCEEDED` | 무비자지만 체류일 초과 → 비자 필요 |
| `VISA_REQUIRED` | 원래부터 비자 필요 |
| `UNVERIFIED` | 데이터 미수집/파싱 실패 — 영사관 확인 필요 (절대 "무비자 OK"로 낙관 처리하지 않음) |

`judgementStale: true`이면 여행 생성 이후 원본 비자 요건 데이터가 바뀌었다는 뜻 — 화면에서 "최신 정보로 새로고침하시겠어요?" 안내에 사용.

**404** — 존재하지 않거나 **다른 사용자 소유**의 여행(구분 없이 404).

### `POST /api/trips/{id}/refresh`
사용자가 명시적으로 동의했을 때만 호출. 판정을 다시 계산해 스냅샷을 덮어쓰고, 기존 준비 일정을 전부 지운 뒤 새로 만든다.

> ⚠️ 이미 완료 체크한 준비 일정(`tasks[].done`)은 새로고침 시 초기화된다 — 앱에서 확인 다이얼로그로 미리 안내할 것.

**응답 200** — TripResponse (위와 동일 형태).
**404** — 존재하지 않거나 다른 사용자 소유.

### `POST /api/trips/{id}/tasks/{taskId}/done`
역산 준비 일정 항목 하나를 완료 처리한다(체크 해제 불가 — 단방향).

**응답 200**
```json
{ "id": 1, "title": "여권 유효기간 확인", "dueDate": "2026-12-13", "done": true }
```
**404** — 여행 없음/소유권 없음, 또는 해당 여행에 그 taskId가 없음.

### `GET /api/trips/{id}/checklist`
이 여행 생성 시점에 스냅샷으로 복사된 준비물 체크리스트(우선순위순).

**응답 200**
```json
[
  { "id": 1, "category": "서류", "title": "여권", "description": "유효기간 6개월 이상", "priority": 1, "checked": false }
]
```
> 진행률(%)은 서버가 계산해 내려주지 않는다 — 클라이언트가 `checked` 개수를 세어 계산한다.

**404** — 여행 없음/소유권 없음.

### `POST /api/trips/{id}/checklist/{itemId}/check`
체크리스트 항목 하나를 체크/체크 해제(양방향, 요청 바디의 `checked` 값을 그대로 반영).

**요청**
```json
{ "checked": true }
```
`checked` 필드 누락 시 400.

**응답 200**
```json
{ "id": 1, "category": "서류", "title": "여권", "description": "유효기간 6개월 이상", "priority": 1, "checked": true }
```
**404** — 여행 없음/소유권 없음, 또는 해당 여행에 그 itemId가 없음.

---

## 6. 주변 정보 (Places 프록시)

### `GET /api/places/nearby`
Google Places API 프록시(서버가 키를 대신 들고 있어 앱에 키가 노출되지 않는다).

**쿼리 파라미터**
| 이름 | 필수 | 기본값 | 설명 |
|---|---|---|---|
| `lat` | ✓ | - | 위도 |
| `lng` | ✓ | - | 경도 |
| `radius` | - | 1000 | 반경(m) |
| `category` | ✓ | - | `TOURIST` \| `RESTAURANT` \| `PHARMACY` \| `ATM` |

**응답 200**
```json
[
  { "id": "p1", "name": "○○ 사원", "category": "TOURIST", "address": "...", "lat": 21.0, "lng": 105.8 }
]
```
**400** — `category`에 정의되지 않은 값.

---

## 7. 번역 (Translate 프록시)

### `POST /api/translate`
Google Cloud Translation API 프록시.

**요청**
```json
{ "text": "화장실이 어디예요?", "targetLanguage": "vi", "sourceLanguage": null }
```
`sourceLanguage`를 `null`로 보내면 서버(번역 엔진)가 자동 감지한다. `text`/`targetLanguage`는 필수.

**응답 200**
```json
{ "translatedText": "Nhà vệ sinh ở đâu?", "detectedSourceLanguage": "ko" }
```
**400** — `text`/`targetLanguage` 누락 또는 공백.
**502** — Google API 재시도(1회) 후에도 실패.

---

## 8. 발걸음 체크인 · 걸음수 동기화 (다기기 복원 지원)

클라이언트 로컬 drift DB에 쌓인 기록을 배치로 서버에 올리고(`POST`), 기기 변경/재설치 시 되찾아온다(`GET`).

### `POST /api/checkins`
체크인(방문 기록) 배치 업로드. 배열로 여러 건을 한 번에 보낸다.

**요청**
```json
[
  { "localId": 1, "lat": 10.8, "lng": 106.6, "countryIso": "VN",
    "recordedAt": "2026-12-20T09:00:00.000Z", "source": "AUTO" }
]
```
| 필드 | 검증 |
|---|---|
| `localId` | 클라이언트 로컬 PK(응답 매칭용, 서버는 저장 안 함) |
| `countryIso` | 필수 |
| `recordedAt` | 필수, ISO-8601 instant |
| `source` | 필수, `AUTO` \| `MANUAL` \| `IMPORT` |

**응답 200** — `localId` 순서 그대로, 서버가 부여한 id와 매핑:
```json
[ { "localId": 1, "serverId": "42" } ]
```
> **재전송해도 안전(멱등)**: 같은 사용자의 같은 `recordedAt`이면 새로 만들지 않고 기존 행을 그대로 반환한다.

**400** — 검증 실패 또는 알 수 없는 `countryIso`.

### `GET /api/checkins`
로그인한 사용자의 전체 체크인 복원 조회(페이지네이션 없음).

**응답 200**
```json
[
  { "id": 42, "lat": 10.8, "lng": 106.6, "countryIso": "VN",
    "recordedAt": "2026-12-20T09:00:00Z", "source": "AUTO" }
]
```

### `POST /api/daily-steps`
일별 걸음 수 배치 업로드.

**요청**
```json
[ { "localId": 1, "date": "2026-12-20", "countryIso": "VN", "stepCount": 8000 } ]
```
| 필드 | 검증 |
|---|---|
| `date` | 필수. **`yyyy-MM-dd` 순수 날짜 문자열만** — 시각/타임존 없음. 서버는 어떤 타임존 변환도 하지 않으므로, "사용자의 로컬 달력 날짜"를 정확히 클라이언트가 계산해서 보내야 한다(자정 근처 UTC instant를 그대로 보내면 하루 밀릴 수 있다). |
| `countryIso` | 필수 |
| `stepCount` | 0 이상 |

**응답 200** — checkins와 동일한 `{localId, serverId}` 매핑.
> **재전송하면 덮어씀(upsert)**: 같은 사용자·같은 날짜·같은 국가 조합이면 `stepCount`를 최신값으로 갱신한다(체크인과 반대 — 하루의 최종 걸음수를 반영해야 하므로).

**400** — 검증 실패 또는 알 수 없는 `countryIso`.

### `GET /api/daily-steps`
로그인한 사용자의 전체 일별 걸음 수 복원 조회(페이지네이션 없음).

**응답 200**
```json
[ { "id": 7, "date": "2026-12-20", "countryIso": "VN", "stepCount": 8000 } ]
```

---

## 9. 실시간 그룹 위치공유 (WebSocket / STOMP)

REST가 아니라 STOMP-over-WebSocket. 좌표는 **서버에 저장하지 않는다** — 같은 방을 구독 중인 클라이언트에게 즉시 중계만 한다.

### 연결
```
WS /ws
```
- SockJS 미사용, 순수 WebSocket.
- HTTP 핸드셰이크 자체는 인증 없이 통과하지만(`/ws/**`), **STOMP `CONNECT` 프레임의 네이티브 헤더**에 Firebase ID 토큰을 실어야 한다:
  ```
  Authorization: Bearer <Firebase ID Token>
  ```
  토큰이 없거나 무효하면 연결이 즉시 끊긴다. 이후 같은 세션의 모든 SEND/SUBSCRIBE는 이 시점에 고정된 사용자로 처리된다.

### 위치 전송
```
SEND /app/location
```
```json
{ "roomId": "room-1", "lat": 37.5, "lng": 127.0, "ts": 1700000000000 }
```
`ts`는 클라이언트 로컬 epoch millis. **`uid` 필드는 보내지 않는다** — 보내도 무시된다(서버가 CONNECT 시점의 인증된 사용자로만 채운다, 위조 불가).

### 위치 구독
```
SUBSCRIBE /topic/group/{roomId}/location
```
```json
{ "uid": "firebase-uid-abc", "lat": 37.5, "lng": 127.0, "ts": 1700000000000 }
```
`uid`는 발신자의 실제 인증된 uid(서버가 채움). `roomId`는 초대 코드를 통해서만 알 수 있는 비공개 값이라는 전제 하에, "로그인 + roomId를 아는 사람"까지만 최소 인가 보장한다 — **그룹 멤버십(누가 이 방에 실제로 속해 있는지) 검증은 v1 범위에서 의도적으로 생략**돼 있다(방 나간 사람도 roomId를 기억하면 계속 구독 가능한 잔여 리스크 있음, 캡스톤 규모에서 수용).

---

## 부록: 국가 코드/enum 참고

- `PlaceCategory`: `TOURIST`, `RESTAURANT`, `PHARMACY`, `ATM`
- `source`(체크인): `AUTO`, `MANUAL`, `IMPORT`
- `VisaVerdict`: `VISA_FREE_OK`, `VISA_FREE_EXCEEDED`, `VISA_REQUIRED`, `UNVERIFIED`
- 여행경보 `level`: 1~4 (실제 등급), 0 (파싱 실패/UNKNOWN)

## 미구현 / 알려진 제약

- 배포된 서버 URL 없음(로컬 개발 전용, 배포는 별도 작업 필요).
- 한국수출입은행 API 키(`KOREA_EXIM_API_KEY`) 미발급 — 환율 필드명 실 API 미검증(TODO 주석 있음).
- 환전 알림(FCM) 기능 없음 — 이번 범위 밖.
- 그룹 위치공유 참여자 검증(Firestore) 없음 — 9절 참고.
