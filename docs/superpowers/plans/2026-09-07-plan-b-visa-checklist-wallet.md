# Plan B — 앱: 여행계획·비자 화면·로컬 알람·준비물·경비지갑 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 여행계획을 입력하면 서버 비자 판정 결과와 역산 준비 일정이 화면에 나타나고, 각 일정 항목마다 로컬 알람이 예약되며, 목적지 국가의 준비물을 체크리스트로 관리할 수 있다. 여유가 있으면 환율 확인과 로컬 경비 지갑까지 더한다.

**Architecture:** Flutter 앱이 Phase 0에서 만든 `apiClientProvider`(dio + Firebase ID Token 인터셉터)로 Spring 서버의 `POST /api/trips`, `GET /api/trips/{id}`, `GET /api/countries/{iso2}`, `GET /api/countries/{iso2}/checklist`를 호출해 여행/비자/준비물 데이터를 가져온다. 서버가 반환한 역산 일정(`trip_task`)마다 `flutter_local_notifications`로 기기 로컬 알람을 예약한다(서버 푸시 없음). 준비물 체크 여부와 경비 지갑은 서버에 저장하지 않는다 — 체크 여부는 `SharedPreferences`, 지갑은 `drift`(SQLite) 로컬 테이블로 관리한다.

> **Plan A 계약 추가분 (2026-09-12 리뷰 반영, 이 문서 작성 이후 확정됨)** — 이 계획 구현 시 아래 두 가지를 반영해야 한다. 자세한 서버 쪽 근거는 `2026-09-07-plan-a-server-data-pipeline.md` Task 6/7 참고.
> 1. `GET /api/trips/{id}` 응답에 `judgementStale: boolean`이 추가된다. `true`면 비자 판정 기준이 여행 생성 이후 바뀐 것이므로, 화면에 "판정 기준이 바뀌었어요, 새로고침할까요?"를 띄우고 동의 시 `POST /api/trips/{id}/refresh`를 호출한다(응답은 `GET`과 동일한 형식). 새로고침하면 서버가 `trip_task`를 다시 만들므로 이미 완료 체크한 항목·예약된 로컬 알람도 화면에서 같이 재예약해야 한다.
> 2. 준비물 체크 상태는 `SharedPreferences`(로컬 전용)가 아니라 **서버 API로 동기화**한다 — `GET /api/trips/{tripId}/checklist`(응답 `[{id, category, title, description, priority, checked}]`)와 `POST /api/trips/{tripId}/checklist/{itemId}/check`(바디 `{checked}`)를 쓴다. 진행률은 이 목록의 `checked` 개수를 세어 클라이언트에서 계산한다(별도 API 없음).

**Tech Stack:** Flutter 3.x / Riverpod / go_router / dio (Phase 0 기반) · `flutter_local_notifications` + `timezone` (로컬 알람) · `shared_preferences` (준비물 체크 상태, 활성 여행 ID) · `drift` + `sqlite3_flutter_libs` + `path_provider` (경비 지갑, T3)

**Spec:** `docs/superpowers/specs/2026-09-06-overseas-travel-app-design.md` §6-①②⑦, §7

## Global Constraints

- **이 계획은 앱(`app/`)만 수정한다.** 서버(`server/`) 코드는 건드리지 않는다 — 서버 API는 Plan A(R1)가 구현한다.
- **Phase 0 산출물을 재사용하고 재구현하지 않는다.**
  - 모든 서버 호출은 `app/lib/core/network/api_client.dart`의 `apiClientProvider`(`Provider<Dio>`)가 만든 `Dio` 인스턴스를 주입받아 쓴다. 새 `Dio()`를 직접 만들지 않는다.
  - 로그인/토큰은 `app/lib/core/auth/auth_repository.dart`의 `AuthRepository`를 그대로 쓴다.
  - `app/lib/features/visa/visa_page.dart`, `app/lib/features/checklist/checklist_page.dart`는 Phase 0 Task 7/9가 만든 빈 껍데기다. 이 계획이 그 내용을 실제 화면으로 교체한다.
- **상태관리는 Riverpod의 `Provider`/`FutureProvider`/`StateNotifierProvider`를 쓴다.** Phase 0가 `riverpod_generator`(코드젠)를 쓰지 않으므로 이 계획도 코드젠을 도입하지 않는다.
- **파일 구조**: `app/lib/features/<feature>/` 아래 `models/`, `data/`(API 클라이언트·provider), `widgets/`(화면·위젯) 하위 폴더를 둔다. Phase 0의 단일 파일 관례를 이 계획에서 기능이 커지는 지점부터 확장한다.
- **날짜는 서버와 `yyyy-MM-dd` ISO-8601 문자열로 주고받는다.** `DateTime.parse` / `DateFormat('yyyy-MM-dd').format`을 쓴다.
- **패키지 루트**: `com.travelfootsteps`. 알림 채널 ID는 `com.travelfootsteps.visa_alarms`를 쓴다.
- **서버 계약은 스펙 §7을 신뢰하고 목(mock)으로 테스트한다.** Plan A가 실제로 구현하기 전이므로, 이 계획의 모든 서버 호출 테스트는 `Dio.httpClientAdapter`를 스텁으로 교체해 실제 네트워크 없이 검증한다. Plan A의 실제 응답이 이 계획이 가정한 JSON 모양과 다르면, 고칠 곳은 각 기능의 `fromJson` 팩토리 하나로 좁혀지도록 모델을 설계한다.
- **T3 우선순위 규칙 (스펙 §6, §10)**: Task 1~6(비자 입력·판정·알람·준비물)은 **T1 — 반드시** 구현한다. Task 7~8(환율·경비 지갑)은 **T3 — 여유 시**다. 일정이 밀리면 **Task 8을 가장 먼저 자르고, 그다음 Task 7을 자른다.** Task 1~6은 어떤 상황에서도 자르지 않는다.
- **경비 지갑은 서버에 저장하지 않는다 (스펙 §6-⑦, §7).** `wallet_entry`는 drift 로컬 테이블로만 존재한다. 다인 정산·예산경고·영수증 OCR·서버 동기화는 만들지 않는다.

---

## 이 계획이 서버 계약에 대해 내린 가정 (Plan A 연동 시 확인 필요)

스펙 §7의 API 목록은 각 엔드포인트의 정확한 요청/응답 JSON 필드까지는 정의하지 않는다. 이 계획은 §6-①의 판정 로직 설명과 §7의 데이터 모델을 근거로 아래처럼 구체화했다. Plan A(R1)가 실제 서버를 만들 때 이 가정과 다르면, 아래 표에 적힌 모델 파일의 `fromJson`만 고치면 된다.

| 엔드포인트 | 가정한 응답 모양 | 근거 |
|---|---|---|
| `POST /api/trips`, `GET /api/trips/{id}` | `Trip` — `id`, `countryIso2`, `countryNameKo`, `departDate`, `returnDate`, `passportExpiry`, `visaResult{verdict, stayDays, visaFreeDays, passportOk, passportValidityMonths, passportShortfallDays}`, `tasks[{id, title, dueDate, done}]` | §6-①의 판정 로직 4단계(비자/여권/역산 일정)를 그대로 필드로 옮김 |
| `POST /api/trips/{id}/tasks/{taskId}/done` | 요청 본문 없음, 응답 `{id, title, dueDate, done: true}` | §7 `trip_task.done` 컬럼과 대칭 |
| `GET /api/countries/{iso2}` | `CountryDetail` — §7 `country` 테이블 컬럼을 camelCase로 그대로 노출 | Phase 0 Task 6의 `CountryResponse`가 이미 같은 변환 규칙을 씀 |
| `GET /api/countries/{iso2}/checklist` | `ChecklistTemplate[]` — `id`, `category`, `title`, `description`, `priority`. **`checked` 필드는 없다** | §7 `checklist_template`은 국가 공통 템플릿이며 `trip_id`를 갖지 않는다. 체크 여부(`trip_checklist.checked`)를 읽거나 쓰는 엔드포인트가 스펙에 없으므로, 이 계획은 **체크 상태를 서버에 동기화하지 않고 기기 로컬(`SharedPreferences`)에만 저장한다.** 나중에 Plan A가 관련 엔드포인트를 만들면 `ChecklistCheckedStore`(Task 6) 하나만 서버 동기화로 교체하면 된다 |
| `GET /api/exchange-rates/{currencyCode}` | `{currencyCode, krwRate, baseDate}` — `krwRate`는 해당 통화 1단위당 원화 금액 | §7 `exchange_rate(currency_code, krw_rate, base_date)`를 그대로 노출 |

---

## File Structure

```
app/
├── pubspec.yaml                                     의존성 추가 (아래 각 Task에서)
├── lib/
│   ├── router.dart                                  Modify: 비자 탭 하위 라우트 추가
│   └── features/
│       ├── visa/
│       │   ├── visa_page.dart                       Modify: 진입점 (활성 여행 유무로 분기)
│       │   ├── models/
│       │   │   └── trip.dart                        Trip, VisaResult, VisaVerdict, TripTask
│       │   ├── data/
│       │   │   ├── trip_api.dart                     TripApi (postTrip/getTrip/markTaskDone)
│       │   │   └── trip_providers.dart                activeTripIdProvider, tripProvider
│       │   ├── widgets/
│       │   │   ├── trip_form_page.dart                여행계획 입력 폼
│       │   │   ├── visa_result_page.dart              비자 결과 + 역산 타임라인
│       │   │   └── visa_verdict_badge.dart            판정 배지 위젯
│       │   └── notifications/
│       │       └── alarm_scheduler.dart               flutter_local_notifications 래퍼
│       ├── checklist/
│       │   ├── checklist_page.dart                    Modify: 진입점 (활성 여행의 국가 체크리스트)
│       │   ├── models/
│       │   │   └── checklist.dart                     CountryDetail, ChecklistTemplate
│       │   ├── data/
│       │   │   ├── checklist_api.dart                  ChecklistApi (getCountryDetail/getChecklist)
│       │   │   ├── checklist_checked_store.dart        SharedPreferences 기반 로컬 체크 상태
│       │   │   └── checklist_providers.dart
│       │   └── widgets/
│       │       ├── country_info_header.dart            플러그/전압/화폐 헤더
│       │       └── checklist_progress_bar.dart
│       └── wallet/                                     T3 — 여유 없으면 Task 7, 8부터 자른다
│           ├── data/
│           │   ├── exchange_rate_api.dart              ExchangeRateApi
│           │   └── wallet_database.dart                drift WalletEntries 테이블
│           └── widgets/
│               ├── exchange_rate_card.dart              환율 표시 + KRW⇄현지 환산기
│               └── wallet_page.dart                     경비 지갑 CRUD 화면
└── test/
    ├── support/
    │   └── stub_http_client_adapter.dart               Dio 목 응답 헬퍼 (Task 1에서 생성, 이후 재사용)
    ├── visa/
    │   ├── trip_test.dart
    │   ├── trip_api_test.dart
    │   ├── alarm_scheduling_test.dart
    │   └── visa_verdict_badge_test.dart
    ├── checklist/
    │   ├── checklist_api_test.dart
    │   └── checklist_checked_store_test.dart
    └── wallet/
        ├── exchange_rate_api_test.dart
        └── wallet_database_test.dart
```

---

### Task 1: 서버 목(mock) 테스트 헬퍼 + Trip 모델

**Files:**
- Create: `app/test/support/stub_http_client_adapter.dart`
- Create: `app/lib/features/visa/models/trip.dart`
- Test: `app/test/visa/trip_test.dart`

**Interfaces:**
- Consumes: 없음 (이 계획의 첫 태스크)
- Produces:
  - `StubHttpClientAdapter` — `StubHttpClientAdapter({required String path, required int statusCode, required String body})`. `Dio.httpClientAdapter`에 꽂으면 해당 경로 요청에 고정된 JSON을 돌려준다. Task 2, 5, 7이 재사용한다.
  - `Trip`, `VisaResult`, `VisaVerdict` (enum), `TripTask` — `Trip.fromJson(Map<String, dynamic>)`. Task 2~4가 이 모델을 소비한다.

- [ ] **Step 1: 목 어댑터 작성**

`app/test/support/stub_http_client_adapter.dart`:

```dart
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 지정한 path로 오는 요청에 고정된 JSON 응답을 돌려준다.
/// 실제 네트워크를 타지 않고 API 클라이언트를 단위 테스트하기 위한 용도.
class StubHttpClientAdapter implements HttpClientAdapter {
  StubHttpClientAdapter({
    required this.path,
    required this.statusCode,
    required this.body,
  });

  final String path;
  final int statusCode;
  final String body;

  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (!options.path.contains(path)) {
      return ResponseBody.fromString(
        '{"error":"unexpected path ${options.path}"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 2: 실패하는 모델 테스트 작성**

`app/test/visa/trip_test.dart`:

```dart
import 'package:app/features/visa/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const json = {
    'id': 1,
    'countryIso2': 'VN',
    'countryNameKo': '베트남',
    'departDate': '2026-12-20',
    'returnDate': '2027-01-09',
    'passportExpiry': '2027-03-15',
    'visaResult': {
      'verdict': 'VISA_FREE_OK',
      'stayDays': 20,
      'visaFreeDays': 45,
      'passportOk': false,
      'passportValidityMonths': 6,
      'passportShortfallDays': 11,
    },
    'tasks': [
      {'id': 101, 'title': '여권 재발급 신청', 'dueDate': '2026-09-21', 'done': false},
      {'id': 102, 'title': '항공권·숙소 확정', 'dueDate': '2026-11-05', 'done': false},
    ],
  };

  test('Trip.fromJson이 판정 결과와 일정 목록을 파싱한다', () {
    final trip = Trip.fromJson(json);

    expect(trip.id, 1);
    expect(trip.countryNameKo, '베트남');
    expect(trip.departDate, DateTime(2026, 12, 20));
    expect(trip.visaResult.verdict, VisaVerdict.visaFreeOk);
    expect(trip.visaResult.passportOk, isFalse);
    expect(trip.visaResult.passportShortfallDays, 11);
    expect(trip.tasks, hasLength(2));
    expect(trip.tasks.first.title, '여권 재발급 신청');
  });

  test('알 수 없는 verdict 문자열은 unverified로 안전하게 degrade한다', () {
    final trip = Trip.fromJson({
      ...json,
      'visaResult': {...json['visaResult'] as Map, 'verdict': 'SOMETHING_NEW'},
    });

    expect(trip.visaResult.verdict, VisaVerdict.unverified);
  });

  group('TripTask.isPastDue', () {
    test('마감일이 지났고 완료 전이면 true다', () {
      final task = TripTask(
        id: 1,
        title: '최종 서류 점검',
        dueDate: DateTime.now().subtract(const Duration(days: 1)),
        done: false,
      );

      expect(task.isPastDue, isTrue);
    });

    test('완료된 항목은 마감이 지나도 false다', () {
      final task = TripTask(
        id: 1,
        title: '최종 서류 점검',
        dueDate: DateTime.now().subtract(const Duration(days: 1)),
        done: true,
      );

      expect(task.isPastDue, isFalse);
    });
  });
}
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd app && flutter test test/visa/trip_test.dart
```

기대: 컴파일 실패 — `app/features/visa/models/trip.dart`를 찾을 수 없음.

- [ ] **Step 4: 모델 구현**

`app/lib/features/visa/models/trip.dart`:

```dart
enum VisaVerdict {
  visaFreeOk('VISA_FREE_OK'),
  visaFreeExceeded('VISA_FREE_EXCEEDED'),
  visaRequired('VISA_REQUIRED'),
  unverified('UNVERIFIED');

  const VisaVerdict(this.wireValue);

  final String wireValue;

  static VisaVerdict fromWire(String value) => VisaVerdict.values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => VisaVerdict.unverified,
      );
}

class VisaResult {
  const VisaResult({
    required this.verdict,
    required this.stayDays,
    this.visaFreeDays,
    required this.passportOk,
    this.passportValidityMonths,
    this.passportShortfallDays,
  });

  final VisaVerdict verdict;
  final int stayDays;

  /// Tier B 미검증 국가는 null일 수 있다 — "영사관 확인 필요"로 표시한다.
  final int? visaFreeDays;

  final bool passportOk;
  final int? passportValidityMonths;
  final int? passportShortfallDays;

  factory VisaResult.fromJson(Map<String, dynamic> json) => VisaResult(
        verdict: VisaVerdict.fromWire(json['verdict'] as String),
        stayDays: json['stayDays'] as int,
        visaFreeDays: json['visaFreeDays'] as int?,
        passportOk: json['passportOk'] as bool,
        passportValidityMonths: json['passportValidityMonths'] as int?,
        passportShortfallDays: json['passportShortfallDays'] as int?,
      );
}

class TripTask {
  const TripTask({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.done,
  });

  final int id;
  final String title;
  final DateTime dueDate;
  final bool done;

  /// 마감일이 지났는데 아직 완료되지 않았다 — 스펙 §6-①: "지금 바로"로 표시한다.
  bool get isPastDue => !done && dueDate.isBefore(DateTime.now());

  factory TripTask.fromJson(Map<String, dynamic> json) => TripTask(
        id: json['id'] as int,
        title: json['title'] as String,
        dueDate: DateTime.parse(json['dueDate'] as String),
        done: json['done'] as bool,
      );

  TripTask copyWith({bool? done}) => TripTask(
        id: id,
        title: title,
        dueDate: dueDate,
        done: done ?? this.done,
      );
}

class Trip {
  const Trip({
    required this.id,
    required this.countryIso2,
    required this.countryNameKo,
    required this.departDate,
    required this.returnDate,
    required this.passportExpiry,
    required this.visaResult,
    required this.tasks,
  });

  final int id;
  final String countryIso2;
  final String countryNameKo;
  final DateTime departDate;
  final DateTime returnDate;
  final DateTime passportExpiry;
  final VisaResult visaResult;
  final List<TripTask> tasks;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as int,
        countryIso2: json['countryIso2'] as String,
        countryNameKo: json['countryNameKo'] as String,
        departDate: DateTime.parse(json['departDate'] as String),
        returnDate: DateTime.parse(json['returnDate'] as String),
        passportExpiry: DateTime.parse(json['passportExpiry'] as String),
        visaResult: VisaResult.fromJson(json['visaResult'] as Map<String, dynamic>),
        tasks: (json['tasks'] as List)
            .map((e) => TripTask.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Trip replaceTask(TripTask updated) => Trip(
        id: id,
        countryIso2: countryIso2,
        countryNameKo: countryNameKo,
        departDate: departDate,
        returnDate: returnDate,
        passportExpiry: passportExpiry,
        visaResult: visaResult,
        tasks: [for (final t in tasks) if (t.id == updated.id) updated else t],
      );
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd app && flutter test test/visa/trip_test.dart
```

기대: 4개 테스트 모두 PASS.

- [ ] **Step 6: 커밋**

```bash
git add app/test/support/stub_http_client_adapter.dart app/lib/features/visa/models app/test/visa/trip_test.dart
git commit -m "feat(app): Trip 모델과 서버 목 테스트 헬퍼"
```

---

### Task 2: 여행계획 입력 폼 → `POST /api/trips`

**Files:**
- Create: `app/lib/features/visa/data/trip_api.dart`
- Create: `app/lib/features/visa/data/trip_providers.dart`
- Create: `app/lib/features/visa/widgets/trip_form_page.dart`
- Modify: `app/lib/router.dart`
- Test: `app/test/visa/trip_api_test.dart`

**Interfaces:**
- Consumes: Task 1의 `Trip.fromJson`, `StubHttpClientAdapter`, Phase 0 Task 9의 `apiClientProvider`
- Produces:
  - `TripApi` — `TripApi(this._dio)`; `Future<Trip> createTrip({required String countryIso2, required DateTime departDate, required DateTime returnDate, required DateTime passportExpiry})`; `Future<Trip> getTrip(int id)`
  - `tripApiProvider` (`Provider<TripApi>`)
  - `activeTripIdProvider` — `StateNotifierProvider<ActiveTripIdController, int?>`, `SharedPreferences` 키 `active_trip_id`로 영속화. Task 3, 6이 "현재 활성 여행"을 여기서 읽는다.
  - go_router 경로 `AppRoutes.visaNew = '/visa/new'`

- [ ] **Step 1: 실패하는 API 테스트 작성**

`app/test/visa/trip_api_test.dart`:

```dart
import 'package:app/features/visa/data/trip_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_http_client_adapter.dart';

const _responseJson = '''
{
  "id": 7,
  "countryIso2": "VN",
  "countryNameKo": "베트남",
  "departDate": "2026-12-20",
  "returnDate": "2027-01-09",
  "passportExpiry": "2027-03-15",
  "visaResult": {
    "verdict": "VISA_FREE_EXCEEDED",
    "stayDays": 20,
    "visaFreeDays": 15,
    "passportOk": true,
    "passportValidityMonths": 6,
    "passportShortfallDays": null
  },
  "tasks": []
}
''';

void main() {
  late Dio dio;
  late StubHttpClientAdapter adapter;
  late TripApi api;

  setUp(() {
    adapter = StubHttpClientAdapter(path: '/api/trips', statusCode: 200, body: _responseJson);
    dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter;
    api = TripApi(dio);
  });

  test('createTrip이 날짜를 yyyy-MM-dd 문자열로 전송하고 Trip을 파싱한다', () async {
    final trip = await api.createTrip(
      countryIso2: 'VN',
      departDate: DateTime(2026, 12, 20),
      returnDate: DateTime(2027, 1, 9),
      passportExpiry: DateTime(2027, 3, 15),
    );

    expect(trip.id, 7);
    expect(trip.visaResult.verdict.name, 'visaFreeExceeded');

    final sent = adapter.lastRequest!.data as Map<String, dynamic>;
    expect(sent['countryIso2'], 'VN');
    expect(sent['departDate'], '2026-12-20');
    expect(sent['returnDate'], '2027-01-09');
    expect(sent['passportExpiry'], '2027-03-15');
  });

  test('getTrip이 id로 GET 요청을 보낸다', () async {
    final trip = await api.getTrip(7);

    expect(trip.id, 7);
    expect(adapter.lastRequest!.method, 'GET');
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/visa/trip_api_test.dart
```

기대: 컴파일 실패 — `app/features/visa/data/trip_api.dart`를 찾을 수 없음.

- [ ] **Step 3: `TripApi` 구현**

`app/lib/features/visa/data/trip_api.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../models/trip.dart';

final _dateFormat = DateFormat('yyyy-MM-dd');

class TripApi {
  TripApi(this._dio);

  final Dio _dio;

  Future<Trip> createTrip({
    required String countryIso2,
    required DateTime departDate,
    required DateTime returnDate,
    required DateTime passportExpiry,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/trips',
      data: {
        'countryIso2': countryIso2,
        'departDate': _dateFormat.format(departDate),
        'returnDate': _dateFormat.format(returnDate),
        'passportExpiry': _dateFormat.format(passportExpiry),
      },
    );
    return Trip.fromJson(response.data!);
  }

  Future<Trip> getTrip(int id) async {
    final response = await _dio.get<Map<String, dynamic>>('/api/trips/$id');
    return Trip.fromJson(response.data!);
  }

  Future<TripTask> markTaskDone(int tripId, int taskId) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/api/trips/$tripId/tasks/$taskId/done');
    return TripTask.fromJson(response.data!);
  }
}

final tripApiProvider = Provider<TripApi>((ref) => TripApi(ref.watch(apiClientProvider)));
```

`flutter pub add intl`를 먼저 실행해 의존성을 추가한다.

```bash
cd app && flutter pub add intl shared_preferences
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/visa/trip_api_test.dart
```

기대: 2개 테스트 모두 PASS.

- [ ] **Step 5: 활성 여행 ID 저장소와 provider 작성**

`app/lib/features/visa/data/trip_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip.dart';
import 'trip_api.dart';

const _activeTripIdKey = 'active_trip_id';

/// 현재 화면에 표시 중인 여행의 서버 id. 앱을 재시작해도 유지된다.
/// 이 앱은 데모 범위상 "활성 여행 1개"만 다룬다 — 여러 여행 목록 조회 API가
/// 스펙에 없기 때문이다 (계획서 상단 "가정" 표 참고).
class ActiveTripIdController extends StateNotifier<int?> {
  ActiveTripIdController(this._prefs) : super(_prefs.getInt(_activeTripIdKey));

  final SharedPreferences _prefs;

  Future<void> set(int tripId) async {
    state = tripId;
    await _prefs.setInt(_activeTripIdKey, tripId);
  }

  Future<void> clear() async {
    state = null;
    await _prefs.remove(_activeTripIdKey);
  }
}

/// main()에서 `SharedPreferences.getInstance()` 결과로 override해야 한다 (Step 6 참고).
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('main.dart에서 override 필요');
});

final activeTripIdProvider =
    StateNotifierProvider<ActiveTripIdController, int?>((ref) {
  return ActiveTripIdController(ref.watch(sharedPreferencesProvider));
});

/// 활성 여행이 없으면 null. 있으면 서버에서 최신 상태를 가져온다.
final activeTripProvider = FutureProvider<Trip?>((ref) async {
  final tripId = ref.watch(activeTripIdProvider);
  if (tripId == null) return null;
  return ref.watch(tripApiProvider).getTrip(tripId);
});
```

- [ ] **Step 6: `main.dart`에 `SharedPreferences` override 추가**

`app/lib/main.dart`를 아래로 교체한다 (Phase 0 Task 8이 만든 Firebase 초기화 부분은 그대로 두고, `ProviderScope`의 `overrides`만 추가한다).

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'features/visa/data/trip_providers.dart';
import 'router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: TravelFootstepsApp(router: createRouter(isLoggedIn: false)),
    ),
  );
}
```

> Phase 0 Task 8에서 이미 `Firebase.initializeApp()`을 붙였다면 그 내용을 유지하고 `overrides`만 추가한다. 이 계획은 `main.dart`의 인증 배선(Task 8 산출물)을 바꾸지 않는다.

- [ ] **Step 7: 여행계획 입력 폼 작성**

`app/lib/features/visa/widgets/trip_form_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/trip_api.dart';
import '../data/trip_providers.dart';

final _display = DateFormat('yyyy-MM-dd');

class TripFormPage extends ConsumerStatefulWidget {
  const TripFormPage({super.key});

  @override
  ConsumerState<TripFormPage> createState() => _TripFormPageState();
}

class _TripFormPageState extends ConsumerState<TripFormPage> {
  final _countryController = TextEditingController(text: 'VN');
  DateTime? _departDate;
  DateTime? _returnDate;
  DateTime? _passportExpiry;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(ValueChanged<DateTime> onPicked, DateTime? current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) onPicked(picked);
  }

  bool get _canSubmit =>
      _countryController.text.trim().length == 2 &&
      _departDate != null &&
      _returnDate != null &&
      _passportExpiry != null &&
      !_submitting;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final trip = await ref.read(tripApiProvider).createTrip(
            countryIso2: _countryController.text.trim().toUpperCase(),
            departDate: _departDate!,
            returnDate: _returnDate!,
            passportExpiry: _passportExpiry!,
          );
      await ref.read(activeTripIdProvider.notifier).set(trip.id);
      ref.invalidate(activeTripProvider);
      if (mounted) context.go('/visa');
    } catch (e) {
      setState(() => _error = '여행계획을 저장하지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('여행계획 입력')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _countryController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 2,
              decoration: const InputDecoration(
                labelText: '목적지 국가 코드 (ISO2, 예: VN)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            _DateTile(
              label: '출발일',
              value: _departDate,
              onTap: () => _pickDate((d) => setState(() => _departDate = d), _departDate),
            ),
            _DateTile(
              label: '귀국일',
              value: _returnDate,
              onTap: () => _pickDate((d) => setState(() => _returnDate = d), _returnDate),
            ),
            _DateTile(
              label: '여권 만료일',
              value: _passportExpiry,
              onTap: () =>
                  _pickDate((d) => setState(() => _passportExpiry = d), _passportExpiry),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            FilledButton(
              onPressed: _canSubmit ? _submit : null,
              child: _submitting
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('비자 판정 받기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.label, required this.value, required this.onTap});

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(value == null ? '선택' : _display.format(value!)),
      onTap: onTap,
    );
  }
}
```

- [ ] **Step 8: 라우터에 `/visa/new` 추가**

`app/lib/router.dart`의 `import` 목록에 아래를 추가한다.

```dart
import 'features/visa/widgets/trip_form_page.dart';
```

`AppRoutes` 클래스에 상수를 추가한다.

```dart
  static const visaNew = '/visa/new';
```

`GoRoute(path: AppRoutes.visa, ...)`가 있는 `ShellRoute`의 `routes` 목록에 형제 라우트를 추가한다 (탭 셸 밖에서 열리는 전체화면 폼이므로 `ShellRoute` 바깥, 최상위 `routes` 배열에 넣는다).

```dart
      GoRoute(
        path: AppRoutes.visaNew,
        builder: (context, state) => const TripFormPage(),
      ),
```

- [ ] **Step 9: 전체 검사**

```bash
cd app && flutter analyze && flutter test
```

기대: analyze 무경고, 테스트 전부 PASS. (`visa_page.dart`는 Task 3에서 교체하므로 아직 폼으로 이동하는 버튼은 없다 — 다음 태스크에서 연결한다.)

- [ ] **Step 10: 커밋**

```bash
git add app/lib/features/visa/data app/lib/features/visa/widgets/trip_form_page.dart app/lib/main.dart app/lib/router.dart app/test/visa/trip_api_test.dart app/pubspec.yaml app/pubspec.lock
git commit -m "feat(app): 여행계획 입력 폼과 POST /api/trips 연동"
```

---

### Task 3: 비자 판정 결과 화면 (배지 + 역산 타임라인)

**Files:**
- Create: `app/lib/features/visa/widgets/visa_verdict_badge.dart`
- Create: `app/lib/features/visa/widgets/visa_result_page.dart`
- Modify: `app/lib/features/visa/visa_page.dart`
- Test: `app/test/visa/visa_verdict_badge_test.dart`

**Interfaces:**
- Consumes: Task 1의 `Trip`/`VisaVerdict`, Task 2의 `activeTripProvider`, `activeTripIdProvider`
- Produces: `VisaVerdictBadge` 위젯 — `VisaVerdictBadge({required VisaVerdict verdict, int? visaFreeDays, int? stayDays})`. `VisaPage`가 최종 화면 진입점이 된다.

- [ ] **Step 1: 실패하는 배지 테스트 작성**

`app/test/visa/visa_verdict_badge_test.dart`:

```dart
import 'package:app/features/visa/models/trip.dart';
import 'package:app/features/visa/widgets/visa_verdict_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('무비자 가능이면 초록 체크 배지를 보여준다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: VisaVerdictBadge(verdict: VisaVerdict.visaFreeOk, visaFreeDays: 45, stayDays: 20),
    ));

    expect(find.textContaining('무비자'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('무비자 체류 초과면 경고 배지와 초과 일수를 보여준다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: VisaVerdictBadge(verdict: VisaVerdict.visaFreeExceeded, visaFreeDays: 15, stayDays: 20),
    ));

    expect(find.textContaining('초과'), findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
  });

  testWidgets('미검증 국가면 영사관 확인 안내를 보여준다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: VisaVerdictBadge(verdict: VisaVerdict.unverified, stayDays: 20),
    ));

    expect(find.textContaining('영사관 확인'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/visa/visa_verdict_badge_test.dart
```

기대: 컴파일 실패 — `visa_verdict_badge.dart`를 찾을 수 없음.

- [ ] **Step 3: 배지 위젯 구현**

`app/lib/features/visa/widgets/visa_verdict_badge.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/trip.dart';

class VisaVerdictBadge extends StatelessWidget {
  const VisaVerdictBadge({
    super.key,
    required this.verdict,
    this.visaFreeDays,
    required this.stayDays,
  });

  final VisaVerdict verdict;
  final int? visaFreeDays;
  final int stayDays;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (verdict) {
      VisaVerdict.visaFreeOk => (
          Icons.check_circle,
          Colors.green,
          '무비자 $visaFreeDays일 이내 → 체류 $stayDays일 OK',
        ),
      VisaVerdict.visaFreeExceeded => (
          Icons.error,
          Colors.orange,
          '무비자 $visaFreeDays일 초과 (체류 $stayDays일) → 비자 필요',
        ),
      VisaVerdict.visaRequired => (
          Icons.error,
          Colors.orange,
          '비자 필요',
        ),
      VisaVerdict.unverified => (
          Icons.help_outline,
          Colors.grey,
          '자동 판정 불가 — 영사관 확인 필요',
        ),
    };

    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/visa/visa_verdict_badge_test.dart
```

기대: 3개 테스트 모두 PASS.

- [ ] **Step 5: 결과 화면(타임라인 포함) 작성**

`app/lib/features/visa/widgets/visa_result_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/trip_api.dart';
import '../data/trip_providers.dart';
import '../models/trip.dart';
import '../notifications/alarm_scheduler.dart';
import 'visa_verdict_badge.dart';

final _display = DateFormat('MM/dd (E)', 'ko_KR');

class VisaResultPage extends ConsumerWidget {
  const VisaResultPage({super.key, required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${trip.countryNameKo} · ${DateFormat('yyyy-MM-dd').format(trip.departDate)} 출발',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        VisaVerdictBadge(
          verdict: trip.visaResult.verdict,
          visaFreeDays: trip.visaResult.visaFreeDays,
          stayDays: trip.visaResult.stayDays,
        ),
        if (!trip.visaResult.passportOk) ...[
          const SizedBox(height: 8),
          Card(
            color: Colors.red.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '여권 잔여 유효기간 부족 (필요: ${trip.visaResult.passportValidityMonths}개월'
                '${trip.visaResult.passportShortfallDays != null ? ", ${trip.visaResult.passportShortfallDays}일 부족" : ""})'
                ' → 재발급 필요',
                style: TextStyle(color: Colors.red.shade900),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text('역산 준비 일정', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final task in trip.tasks) _TaskRow(trip: trip, task: task),
      ],
    );
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.trip, required this.task});

  final Trip trip;
  final TripTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CheckboxListTile(
      value: task.done,
      title: Text(task.title),
      subtitle: Text(task.isPastDue ? '지금 바로' : _display.format(task.dueDate)),
      secondary: Icon(task.done ? Icons.notifications_off_outlined : Icons.notifications_active_outlined),
      onChanged: (checked) async {
        if (checked != true) return; // 완료 취소는 지원하지 않는다 — 서버 API가 done만 제공한다
        final updated = await ref.read(tripApiProvider).markTaskDone(trip.id, task.id);
        await ref.read(alarmSchedulerProvider).cancelForTask(tripId: trip.id, taskId: task.id);
        ref.invalidate(activeTripProvider);
        // updated는 캐시 무효화 전 즉시 반영용으로만 쓰고 버린다.
        // ignore: unused_local_variable
        final _ = updated;
      },
    );
  }
}
```

- [ ] **Step 6: `VisaPage`를 진입점으로 교체**

`app/lib/features/visa/visa_page.dart` 전체를 아래로 교체한다.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/trip_providers.dart';
import 'widgets/visa_result_page.dart';

class VisaPage extends ConsumerWidget {
  const VisaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(activeTripProvider);

    return tripAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('여행계획을 불러오지 못했습니다\n$e', textAlign: TextAlign.center),
        ),
      ),
      data: (trip) {
        if (trip == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('등록된 여행계획이 없습니다'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.push('/visa/new'),
                    child: const Text('여행계획 만들기'),
                  ),
                ],
              ),
            ),
          );
        }
        return VisaResultPage(trip: trip);
      },
    );
  }
}
```

`AlarmScheduler`(`alarmSchedulerProvider`)는 Task 4에서 만든다. 지금은 아직 존재하지 않으므로 다음 스텝까지는 `flutter analyze`가 이 파일에서 에러를 낸다 — 정상이다.

- [ ] **Step 7: 커밋 (Task 4 완료 후 함께 검증)**

이 태스크의 코드는 Task 4의 `alarm_scheduler.dart`가 있어야 컴파일된다. 지금 커밋하지 말고 Task 4까지 마친 뒤 한 번에 검사·커밋한다. (Task 4의 Step 마지막에서 이 파일들도 함께 커밋한다.)

---

### Task 4: 로컬 알람 (`flutter_local_notifications`)

**Files:**
- Create: `app/lib/features/visa/notifications/alarm_scheduler.dart`
- Test: `app/test/visa/alarm_scheduling_test.dart`

**Interfaces:**
- Consumes: Task 1의 `TripTask`
- Produces:
  - `notificationIdFor(int tripId, int taskId)` — 순수 함수, 결정적 알림 ID 생성
  - `shouldScheduleAlarm(TripTask task, DateTime now)` — 순수 함수, 과거 마감일/완료 항목은 예약하지 않는다
  - `AlarmScheduler` — `Future<void> init()`, `Future<void> requestPermission()`, `Future<void> scheduleForTrip(Trip trip)`, `Future<void> cancelForTask({required int tripId, required int taskId})`
  - `alarmSchedulerProvider` (`Provider<AlarmScheduler>`)

> **왜 서버 푸시가 아니라 로컬 알람인가 (스펙 §6-①)**: 역산 일정은 사용자 본인의 여행 준비 일정이라 다른 사람에게 전달할 필요가 없다. 서버가 매 사용자의 예약 시각마다 FCM을 보내는 구조를 만들 필요 없이, 기기에 예약해 두면 오프라인에서도 울린다.
>
> **플러그인 자체의 OS 스케줄링 동작은 단위 테스트로 검증하지 않는다.** `flutter_local_notifications`는 실제 알림 트레이·정확한 알람 권한 등 플랫폼 API에 의존하므로, 이 태스크는 **예약 여부를 결정하는 순수 로직**(`shouldScheduleAlarm`, `notificationIdFor`)만 단위 테스트하고, 플러그인 호출 자체는 Task 9(수동 실기기 확인)에서 검증한다.

- [ ] **Step 1: 의존성 추가**

```bash
cd app && flutter pub add flutter_local_notifications timezone
```

- [ ] **Step 2: 실패하는 순수 로직 테스트 작성**

`app/test/visa/alarm_scheduling_test.dart`:

```dart
import 'package:app/features/visa/models/trip.dart';
import 'package:app/features/visa/notifications/alarm_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('notificationIdFor', () {
    test('tripId와 taskId가 다르면 다른 id를 낸다', () {
      expect(notificationIdFor(1, 101), isNot(notificationIdFor(1, 102)));
      expect(notificationIdFor(1, 101), isNot(notificationIdFor(2, 101)));
    });

    test('같은 입력이면 항상 같은 id를 낸다 (재예약/취소 시 필요)', () {
      expect(notificationIdFor(7, 101), notificationIdFor(7, 101));
    });

    test('32비트 정수 범위를 넘지 않는다', () {
      expect(notificationIdFor(99999, 99999), lessThan(1 << 31));
    });
  });

  group('shouldScheduleAlarm', () {
    final now = DateTime(2026, 9, 7);

    test('미래 마감일이고 미완료면 예약한다', () {
      final task = TripTask(id: 1, title: 't', dueDate: DateTime(2026, 9, 21), done: false);
      expect(shouldScheduleAlarm(task, now), isTrue);
    });

    test('이미 지난 마감일이면 예약하지 않는다 (지금 바로 로 표시될 항목)', () {
      final task = TripTask(id: 1, title: 't', dueDate: DateTime(2026, 9, 1), done: false);
      expect(shouldScheduleAlarm(task, now), isFalse);
    });

    test('완료된 항목은 예약하지 않는다', () {
      final task = TripTask(id: 1, title: 't', dueDate: DateTime(2026, 9, 21), done: true);
      expect(shouldScheduleAlarm(task, now), isFalse);
    });
  });
}
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd app && flutter test test/visa/alarm_scheduling_test.dart
```

기대: 컴파일 실패 — `alarm_scheduler.dart`를 찾을 수 없음.

- [ ] **Step 4: `AlarmScheduler` 구현**

`app/lib/features/visa/notifications/alarm_scheduler.dart`:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/trip.dart';

const _channelId = 'com.travelfootsteps.visa_alarms';
const _channelName = '비자 준비 알람';

/// tripId, taskId 조합마다 결정적인 알림 id를 만든다.
/// 같은 항목을 다시 예약하거나 취소할 때 같은 id로 찾아야 하므로 해시가 아니라
/// 단순 조합을 쓴다. taskId가 100000을 넘지 않는다고 가정한다 (서버 시퀀스 기준 충분).
int notificationIdFor(int tripId, int taskId) => (tripId % 10000) * 100000 + (taskId % 100000);

/// 과거 마감일(스펙 §6-①: "지금 바로"로 표시되는 항목)이거나 이미 완료된 항목은
/// 알람을 예약하지 않는다.
bool shouldScheduleAlarm(TripTask task, DateTime now) =>
    !task.done && task.dueDate.isAfter(now);

class AlarmScheduler {
  AlarmScheduler(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> init() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: androidInit));

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: '여행 준비 일정(비자·여권·보험 등) 알림',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// 여행의 모든 준비 일정에 대해 알람을 예약한다. 완료됐거나 이미 지난 항목은 건너뛴다.
  Future<void> scheduleForTrip(Trip trip) async {
    final now = DateTime.now();
    for (final task in trip.tasks) {
      if (!shouldScheduleAlarm(task, now)) continue;
      await _plugin.zonedSchedule(
        notificationIdFor(trip.id, task.id),
        '여행 준비: ${task.title}',
        '${trip.countryNameKo} 여행 준비 일정입니다.',
        tz.TZDateTime.from(
          DateTime(task.dueDate.year, task.dueDate.month, task.dueDate.day, 9),
          tz.local,
        ),
        const NotificationDetails(
          android: AndroidNotificationDetails(_channelId, _channelName),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
      );
    }
  }

  Future<void> cancelForTask({required int tripId, required int taskId}) =>
      _plugin.cancel(notificationIdFor(tripId, taskId));
}

final alarmSchedulerProvider =
    Provider<AlarmScheduler>((ref) => AlarmScheduler(FlutterLocalNotificationsPlugin()));
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd app && flutter test test/visa/alarm_scheduling_test.dart
```

기대: 6개 테스트 모두 PASS.

- [ ] **Step 6: 결과 화면 진입 시 알람 예약을 연결**

`app/lib/features/visa/visa_page.dart`의 `data: (trip) { ... }` 분기에서, `trip`이 null이 아닐 때 알람을 예약하도록 `Consumer`의 빌드 이후 훅을 추가한다. `VisaPage`를 아래로 교체한다 (Step 6에서 만든 버전에 알람 예약 호출을 더한 것).

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/trip_providers.dart';
import 'notifications/alarm_scheduler.dart';
import 'widgets/visa_result_page.dart';

class VisaPage extends ConsumerWidget {
  const VisaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(activeTripProvider);

    return tripAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('여행계획을 불러오지 못했습니다\n$e', textAlign: TextAlign.center),
        ),
      ),
      data: (trip) {
        if (trip == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('등록된 여행계획이 없습니다'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.push('/visa/new'),
                    child: const Text('여행계획 만들기'),
                  ),
                ],
              ),
            ),
          );
        }
        // 화면에 표시될 때마다 최신 일정 기준으로 알람을 다시 예약한다.
        // zonedSchedule은 같은 id로 다시 호출하면 기존 예약을 덮어쓴다.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(alarmSchedulerProvider).scheduleForTrip(trip);
        });
        return VisaResultPage(trip: trip);
      },
    );
  }
}
```

- [ ] **Step 7: 앱 시작 시 플러그인 초기화 + 권한 요청 배선**

`app/lib/main.dart`에 초기화 호출을 추가한다. 전체를 아래로 교체한다.

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'features/visa/data/trip_providers.dart';
import 'features/visa/notifications/alarm_scheduler.dart';
import 'router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  await container.read(alarmSchedulerProvider).init();
  await container.read(alarmSchedulerProvider).requestPermission();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: TravelFootstepsApp(router: createRouter(isLoggedIn: false)),
    ),
  );
}
```

`ProviderScope` 대신 `UncontrolledProviderScope`를 쓰는 이유는, 알람 초기화가 위젯 트리 생성 전에 끝나야 첫 프레임부터 `alarmSchedulerProvider`가 준비된 상태이기 때문이다. `ProviderContainer`를 미리 만들어 초기화한 뒤 그 컨테이너를 앱에 넘긴다.

- [ ] **Step 8: Android 매니페스트에 권한 추가**

`app/android/app/src/main/AndroidManifest.xml`의 `<manifest>` 태그 바로 아래(`<application>` 태그 위)에 추가한다.

```xml
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

- [ ] **Step 9: 전체 검사**

```bash
cd app && flutter analyze && flutter test
```

기대: analyze 무경고, 테스트 전부 PASS. (`AndroidManifest.xml` 수정은 `flutter analyze`/`flutter test` 대상이 아니므로 Step 10의 실기기 확인에서만 검증된다.)

- [ ] **Step 10: 커밋 (Task 3 + Task 4 산출물 함께)**

```bash
git add app/lib/features/visa app/lib/main.dart app/lib/router.dart app/test/visa app/android/app/src/main/AndroidManifest.xml app/pubspec.yaml app/pubspec.lock
git commit -m "feat(app): 비자 결과 화면과 flutter_local_notifications 로컬 알람"
```

- [ ] **Step 11: 실기기 수동 확인 (자동화 테스트로 대체 불가)**

에뮬레이터 또는 실기기에서 `flutter run` 후:
1. 여행계획을 오늘부터 며칠 뒤 마감일이 나오도록 입력해 저장한다 (예: 출발일을 100일 뒤로).
2. 결과 화면 진입 시 알림 권한 팝업이 뜨는지 확인한다.
3. Android 설정 → 앱 → 해외여행 발걸음 → 알림에서 "비자 준비 알람" 채널이 생성됐는지 확인한다.
4. 마감일을 오늘로 맞춘 테스트 여행을 만들어 알림이 실제로 울리는지 확인한다 (또는 `adb shell dumpsys alarm | grep travelfootsteps`로 예약된 알람이 있는지 확인한다).

---

### Task 5: 국가 상세 + 준비물 API 클라이언트

**Files:**
- Create: `app/lib/features/checklist/models/checklist.dart`
- Create: `app/lib/features/checklist/data/checklist_api.dart`
- Test: `app/test/checklist/checklist_api_test.dart`

**Interfaces:**
- Consumes: Task 1의 `StubHttpClientAdapter`, Phase 0 Task 9의 `apiClientProvider`
- Produces:
  - `CountryDetail.fromJson`, `ChecklistTemplate.fromJson`
  - `ChecklistApi` — `Future<CountryDetail> getCountryDetail(String iso2)`, `Future<List<ChecklistTemplate>> getChecklist(String iso2)`
  - `checklistApiProvider` (`Provider<ChecklistApi>`)

- [ ] **Step 1: 실패하는 API 테스트 작성**

`app/test/checklist/checklist_api_test.dart`:

```dart
import 'package:app/features/checklist/data/checklist_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_http_client_adapter.dart';

void main() {
  test('getCountryDetail이 국가 상세를 파싱한다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/countries/VN',
      statusCode: 200,
      body: '''
      {
        "isoAlpha2": "VN", "nameKo": "베트남", "nameEn": "Vietnam",
        "continent": "Asia", "tier": "A",
        "plugTypes": "A,C", "voltageV": 220, "frequencyHz": 50,
        "currencyCode": "VND", "cardAcceptance": "MEDIUM", "powerBankWhLimit": 160
      }
      ''',
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter;

    final detail = await ChecklistApi(dio).getCountryDetail('VN');

    expect(detail.nameKo, '베트남');
    expect(detail.voltageV, 220);
    expect(detail.currencyCode, 'VND');
    expect(detail.plugTypes, 'A,C');
  });

  test('getChecklist가 카테고리별 템플릿 목록을 파싱한다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/countries/VN/checklist',
      statusCode: 200,
      body: '''
      [
        {"id": 1, "category": "서류", "title": "여권 사본", "description": null, "priority": 1},
        {"id": 2, "category": "전자기기", "title": "220V 어댑터", "description": "C타입", "priority": 2}
      ]
      ''',
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter;

    final items = await ChecklistApi(dio).getChecklist('VN');

    expect(items, hasLength(2));
    expect(items[0].category, '서류');
    expect(items[1].description, 'C타입');
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/checklist/checklist_api_test.dart
```

기대: 컴파일 실패 — `checklist_api.dart`를 찾을 수 없음.

- [ ] **Step 3: 모델 구현**

`app/lib/features/checklist/models/checklist.dart`:

```dart
class CountryDetail {
  const CountryDetail({
    required this.isoAlpha2,
    required this.nameKo,
    this.nameEn,
    this.continent,
    required this.tier,
    this.plugTypes,
    this.voltageV,
    this.frequencyHz,
    this.currencyCode,
    this.cardAcceptance,
    this.powerBankWhLimit,
  });

  final String isoAlpha2;
  final String nameKo;
  final String? nameEn;
  final String? continent;
  final String tier;
  final String? plugTypes;
  final int? voltageV;
  final int? frequencyHz;
  final String? currencyCode;
  final String? cardAcceptance;
  final int? powerBankWhLimit;

  factory CountryDetail.fromJson(Map<String, dynamic> json) => CountryDetail(
        isoAlpha2: json['isoAlpha2'] as String,
        nameKo: json['nameKo'] as String,
        nameEn: json['nameEn'] as String?,
        continent: json['continent'] as String?,
        tier: json['tier'] as String,
        plugTypes: json['plugTypes'] as String?,
        voltageV: json['voltageV'] as int?,
        frequencyHz: json['frequencyHz'] as int?,
        currencyCode: json['currencyCode'] as String?,
        cardAcceptance: json['cardAcceptance'] as String?,
        powerBankWhLimit: json['powerBankWhLimit'] as int?,
      );
}

class ChecklistTemplate {
  const ChecklistTemplate({
    required this.id,
    required this.category,
    required this.title,
    this.description,
    required this.priority,
  });

  final int id;
  final String category;
  final String title;
  final String? description;
  final int priority;

  factory ChecklistTemplate.fromJson(Map<String, dynamic> json) => ChecklistTemplate(
        id: json['id'] as int,
        category: json['category'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        priority: json['priority'] as int,
      );
}
```

- [ ] **Step 4: API 클라이언트 구현**

`app/lib/features/checklist/data/checklist_api.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../models/checklist.dart';

class ChecklistApi {
  ChecklistApi(this._dio);

  final Dio _dio;

  Future<CountryDetail> getCountryDetail(String iso2) async {
    final response = await _dio.get<Map<String, dynamic>>('/api/countries/$iso2');
    return CountryDetail.fromJson(response.data!);
  }

  Future<List<ChecklistTemplate>> getChecklist(String iso2) async {
    final response = await _dio.get<List<dynamic>>('/api/countries/$iso2/checklist');
    return response.data!
        .map((e) => ChecklistTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final checklistApiProvider =
    Provider<ChecklistApi>((ref) => ChecklistApi(ref.watch(apiClientProvider)));
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd app && flutter test test/checklist/checklist_api_test.dart
```

기대: 2개 테스트 모두 PASS.

- [ ] **Step 6: 커밋**

```bash
git add app/lib/features/checklist/models app/lib/features/checklist/data/checklist_api.dart app/test/checklist/checklist_api_test.dart
git commit -m "feat(app): 국가 상세·준비물 템플릿 API 클라이언트"
```

---

### Task 6: 준비물 체크리스트 화면

**Files:**
- Create: `app/lib/features/checklist/data/checklist_checked_store.dart`
- Create: `app/lib/features/checklist/data/checklist_providers.dart`
- Create: `app/lib/features/checklist/widgets/country_info_header.dart`
- Create: `app/lib/features/checklist/widgets/checklist_progress_bar.dart`
- Modify: `app/lib/features/checklist/checklist_page.dart`
- Test: `app/test/checklist/checklist_checked_store_test.dart`

**Interfaces:**
- Consumes: Task 2의 `activeTripProvider`, `sharedPreferencesProvider`, Task 5의 `ChecklistApi`/`CountryDetail`/`ChecklistTemplate`
- Produces:
  - `ChecklistCheckedStore` — `Set<int> checkedIds(int tripId)`, `Future<void> toggle(int tripId, int templateId)`
  - `checklistCheckedProvider` — `StateNotifierProvider.family<ChecklistCheckedController, Set<int>, int>` (tripId로 분기)

- [ ] **Step 1: 실패하는 저장소 테스트 작성**

`app/test/checklist/checklist_checked_store_test.dart`:

```dart
import 'package:app/features/checklist/data/checklist_checked_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('토글하면 체크되고 다시 토글하면 해제된다', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChecklistCheckedStore(prefs);

    expect(store.checkedIds(tripId: 1), isEmpty);

    await store.toggle(tripId: 1, templateId: 10);
    expect(store.checkedIds(tripId: 1), {10});

    await store.toggle(tripId: 1, templateId: 10);
    expect(store.checkedIds(tripId: 1), isEmpty);
  });

  test('여행마다 체크 상태가 분리된다', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChecklistCheckedStore(prefs);

    await store.toggle(tripId: 1, templateId: 10);
    await store.toggle(tripId: 2, templateId: 10);

    expect(store.checkedIds(tripId: 1), {10});
    expect(store.checkedIds(tripId: 2), {10});

    await store.toggle(tripId: 1, templateId: 10);
    expect(store.checkedIds(tripId: 1), isEmpty);
    expect(store.checkedIds(tripId: 2), {10}); // 다른 여행에 영향 없음
  });

  test('재시작 후에도(SharedPreferences 유지) 상태가 남는다', () async {
    var prefs = await SharedPreferences.getInstance();
    await ChecklistCheckedStore(prefs).toggle(tripId: 1, templateId: 5);

    prefs = await SharedPreferences.getInstance(); // 새 인스턴스 = 재시작 시뮬레이션
    expect(ChecklistCheckedStore(prefs).checkedIds(tripId: 1), {5});
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/checklist/checklist_checked_store_test.dart
```

기대: 컴파일 실패 — `checklist_checked_store.dart`를 찾을 수 없음.

- [ ] **Step 3: 저장소 구현**

`app/lib/features/checklist/data/checklist_checked_store.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// 준비물 체크 여부는 서버에 저장하지 않는다 — 스펙 §7에는 국가 공통
/// checklist_template만 있고, 여행별 체크 상태(trip_checklist.checked)를
/// 읽거나 쓰는 엔드포인트는 없다. 기기 로컬(SharedPreferences)에만 둔다.
class ChecklistCheckedStore {
  ChecklistCheckedStore(this._prefs);

  final SharedPreferences _prefs;

  String _key(int tripId) => 'checklist_checked_$tripId';

  Set<int> checkedIds({required int tripId}) =>
      (_prefs.getStringList(_key(tripId)) ?? const []).map(int.parse).toSet();

  Future<void> toggle({required int tripId, required int templateId}) async {
    final current = checkedIds(tripId: tripId);
    if (!current.add(templateId)) {
      current.remove(templateId);
    }
    await _prefs.setStringList(
      _key(tripId),
      current.map((id) => id.toString()).toList(),
    );
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/checklist/checklist_checked_store_test.dart
```

기대: 3개 테스트 모두 PASS.

- [ ] **Step 5: provider 배선**

`app/lib/features/checklist/data/checklist_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../visa/data/trip_providers.dart';
import '../models/checklist.dart';
import 'checklist_api.dart';
import 'checklist_checked_store.dart';

final checklistCheckedStoreProvider = Provider<ChecklistCheckedStore>(
  (ref) => ChecklistCheckedStore(ref.watch(sharedPreferencesProvider)),
);

/// tripId별 체크된 templateId 집합. toggle 시 invalidate해서 새로 읽는다.
final checklistCheckedProvider =
    Provider.family<Set<int>, int>((ref, tripId) {
  return ref.watch(checklistCheckedStoreProvider).checkedIds(tripId: tripId);
});

final countryDetailProvider =
    FutureProvider.family<CountryDetail, String>((ref, iso2) {
  return ref.watch(checklistApiProvider).getCountryDetail(iso2);
});

final checklistTemplatesProvider =
    FutureProvider.family<List<ChecklistTemplate>, String>((ref, iso2) {
  return ref.watch(checklistApiProvider).getChecklist(iso2);
});
```

- [ ] **Step 6: 국가 정보 헤더 위젯**

`app/lib/features/checklist/widgets/country_info_header.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/checklist.dart';

class CountryInfoHeader extends StatelessWidget {
  const CountryInfoHeader({super.key, required this.detail});

  final CountryDetail detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail.nameKo, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (detail.plugTypes != null)
                  _InfoChip(icon: Icons.power, label: '플러그 ${detail.plugTypes}'),
                if (detail.voltageV != null)
                  _InfoChip(icon: Icons.bolt, label: '${detail.voltageV}V'),
                if (detail.currencyCode != null)
                  _InfoChip(icon: Icons.attach_money, label: detail.currencyCode!),
                if (detail.cardAcceptance != null)
                  _InfoChip(icon: Icons.credit_card, label: '카드 통용도 ${detail.cardAcceptance}'),
                if (detail.powerBankWhLimit != null)
                  _InfoChip(
                      icon: Icons.battery_charging_full,
                      label: '보조배터리 ${detail.powerBankWhLimit}Wh 이하'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}
```

- [ ] **Step 7: 진행률 바 위젯**

`app/lib/features/checklist/widgets/checklist_progress_bar.dart`:

```dart
import 'package:flutter/material.dart';

class ChecklistProgressBar extends StatelessWidget {
  const ChecklistProgressBar({super.key, required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : done / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$done / $total 완료'),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: ratio, minHeight: 8),
        ),
      ],
    );
  }
}
```

- [ ] **Step 8: `ChecklistPage`를 실제 화면으로 교체**

`app/lib/features/checklist/checklist_page.dart` 전체를 아래로 교체한다.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../visa/data/trip_providers.dart';
import 'data/checklist_providers.dart';
import 'widgets/checklist_progress_bar.dart';
import 'widgets/country_info_header.dart';

class ChecklistPage extends ConsumerWidget {
  const ChecklistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(activeTripProvider);

    return tripAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('여행계획을 불러오지 못했습니다\n$e', textAlign: TextAlign.center)),
      data: (trip) {
        if (trip == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('먼저 비자 탭에서 여행계획을 등록하면\n목적지 준비물이 여기 표시됩니다',
                  textAlign: TextAlign.center),
            ),
          );
        }
        return _ChecklistBody(tripId: trip.id, iso2: trip.countryIso2);
      },
    );
  }
}

class _ChecklistBody extends ConsumerWidget {
  const _ChecklistBody({required this.tripId, required this.iso2});

  final int tripId;
  final String iso2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(countryDetailProvider(iso2));
    final templatesAsync = ref.watch(checklistTemplatesProvider(iso2));
    final checkedIds = ref.watch(checklistCheckedProvider(tripId));

    if (detailAsync.isLoading || templatesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (detailAsync.hasError) {
      return Center(child: Text('국가 정보를 불러오지 못했습니다\n${detailAsync.error}'));
    }
    if (templatesAsync.hasError) {
      return Center(child: Text('준비물 목록을 불러오지 못했습니다\n${templatesAsync.error}'));
    }

    final detail = detailAsync.value!;
    final templates = templatesAsync.value!;
    final byCategory = <String, List<int>>{};
    for (var i = 0; i < templates.length; i++) {
      byCategory.putIfAbsent(templates[i].category, () => []).add(i);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CountryInfoHeader(detail: detail),
        const SizedBox(height: 16),
        ChecklistProgressBar(done: checkedIds.length, total: templates.length),
        const SizedBox(height: 16),
        for (final category in byCategory.keys) ...[
          Text(category, style: Theme.of(context).textTheme.titleMedium),
          for (final i in byCategory[category]!)
            CheckboxListTile(
              value: checkedIds.contains(templates[i].id),
              title: Text(templates[i].title),
              subtitle:
                  templates[i].description != null ? Text(templates[i].description!) : null,
              onChanged: (_) async {
                await ref
                    .read(checklistCheckedStoreProvider)
                    .toggle(tripId: tripId, templateId: templates[i].id);
                ref.invalidate(checklistCheckedProvider(tripId));
              },
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
```

- [ ] **Step 9: 전체 검사**

```bash
cd app && flutter analyze && flutter test
```

기대: analyze 무경고, 테스트 전부 PASS.

- [ ] **Step 10: 커밋**

```bash
git add app/lib/features/checklist app/test/checklist/checklist_checked_store_test.dart
git commit -m "feat(app): 준비물 체크리스트 화면 (국가 헤더 + 카테고리 + 진행률)"
```

---

> **여기까지가 T1(반드시)이다.** Task 1~6이 끝나면 스펙 §6-①②의 필수 기능이 시연 가능한 상태다. 일정이 부족하면 아래 Task 7, 8은 **이 순서대로(8부터, 그다음 7)** 자른다 — 스펙 §10 "여유가 없어질 때 자르는 순서" 1번.

---

### Task 7 (T3 — 여유 시): 환율 표시 + KRW⇄현지 환산기

**Files:**
- Create: `app/lib/features/wallet/data/exchange_rate_api.dart`
- Create: `app/lib/features/wallet/widgets/exchange_rate_card.dart`
- Test: `app/test/wallet/exchange_rate_api_test.dart`

**Interfaces:**
- Consumes: Task 5의 `CountryDetail.currencyCode`, Phase 0 Task 9의 `apiClientProvider`
- Produces: `ExchangeRate.fromJson`, `ExchangeRateApi.getRate(String currencyCode)`, `exchangeRateProvider` (`FutureProvider.family<ExchangeRate, String>`), `ExchangeRateCard` 위젯

- [ ] **Step 1: 실패하는 API 테스트 작성**

`app/test/wallet/exchange_rate_api_test.dart`:

```dart
import 'package:app/features/wallet/data/exchange_rate_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_http_client_adapter.dart';

void main() {
  test('getRate가 통화 코드로 환율을 조회한다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/exchange-rates/VND',
      statusCode: 200,
      body: '{"currencyCode":"VND","krwRate":0.054,"baseDate":"2026-09-07"}',
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter;

    final rate = await ExchangeRateApi(dio).getRate('VND');

    expect(rate.currencyCode, 'VND');
    expect(rate.krwRate, 0.054);
  });

  test('krwFrom / localFrom이 서로 역연산이다', () {
    const rate = ExchangeRate(currencyCode: 'VND', krwRate: 0.054, baseDate: '2026-09-07');

    final krw = rate.krwFrom(100000); // 현지 통화 10만 동
    expect(krw, closeTo(5400, 0.01));
    expect(rate.localFrom(krw), closeTo(100000, 0.01));
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/wallet/exchange_rate_api_test.dart
```

기대: 컴파일 실패 — `exchange_rate_api.dart`를 찾을 수 없음.

- [ ] **Step 3: 모델 + API 구현**

`app/lib/features/wallet/data/exchange_rate_api.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class ExchangeRate {
  const ExchangeRate({required this.currencyCode, required this.krwRate, required this.baseDate});

  final String currencyCode;

  /// 해당 통화 1단위당 원화 금액 (§7 exchange_rate.krw_rate)
  final double krwRate;
  final String baseDate;

  double krwFrom(double localAmount) => localAmount * krwRate;
  double localFrom(double krwAmount) => krwRate == 0 ? 0 : krwAmount / krwRate;

  factory ExchangeRate.fromJson(Map<String, dynamic> json) => ExchangeRate(
        currencyCode: json['currencyCode'] as String,
        krwRate: (json['krwRate'] as num).toDouble(),
        baseDate: json['baseDate'] as String,
      );
}

class ExchangeRateApi {
  ExchangeRateApi(this._dio);

  final Dio _dio;

  Future<ExchangeRate> getRate(String currencyCode) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/api/exchange-rates/$currencyCode');
    return ExchangeRate.fromJson(response.data!);
  }
}

final exchangeRateApiProvider =
    Provider<ExchangeRateApi>((ref) => ExchangeRateApi(ref.watch(apiClientProvider)));

final exchangeRateProvider =
    FutureProvider.family<ExchangeRate, String>((ref, currencyCode) {
  return ref.watch(exchangeRateApiProvider).getRate(currencyCode);
});
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/wallet/exchange_rate_api_test.dart
```

기대: 2개 테스트 모두 PASS.

- [ ] **Step 5: 환산기 카드 위젯**

`app/lib/features/wallet/widgets/exchange_rate_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../data/exchange_rate_api.dart';

class ExchangeRateCard extends StatefulWidget {
  const ExchangeRateCard({super.key, required this.rate});

  final ExchangeRate rate;

  @override
  State<ExchangeRateCard> createState() => _ExchangeRateCardState();
}

class _ExchangeRateCardState extends State<ExchangeRateCard> {
  final _krwController = TextEditingController();
  final _localController = TextEditingController();
  bool _editingKrw = true;

  void _onKrwChanged(String text) {
    if (!_editingKrw) return;
    final krw = double.tryParse(text);
    _localController.text = krw == null ? '' : widget.rate.localFrom(krw).toStringAsFixed(0);
  }

  void _onLocalChanged(String text) {
    if (_editingKrw) return;
    final local = double.tryParse(text);
    _krwController.text = local == null ? '' : widget.rate.krwFrom(local).toStringAsFixed(0);
  }

  @override
  void dispose() {
    _krwController.dispose();
    _localController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('오늘의 환율 (${widget.rate.baseDate} 기준)',
                style: Theme.of(context).textTheme.titleMedium),
            Text('1 ${widget.rate.currencyCode} = ${widget.rate.krwRate.toStringAsFixed(2)}원'),
            const SizedBox(height: 12),
            TextField(
              controller: _krwController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'KRW'),
              onTap: () => _editingKrw = true,
              onChanged: _onKrwChanged,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _localController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: widget.rate.currencyCode),
              onTap: () => _editingKrw = false,
              onChanged: _onLocalChanged,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: 전체 검사 후 커밋**

```bash
cd app && flutter analyze && flutter test
git add app/lib/features/wallet/data/exchange_rate_api.dart app/lib/features/wallet/widgets/exchange_rate_card.dart app/test/wallet/exchange_rate_api_test.dart
git commit -m "feat(app): 환율 표시와 KRW/현지통화 환산기 (T3)"
```

> **연동 참고**: 이 카드는 아직 어느 화면에도 배치돼 있지 않다. Task 8에서 만드는 `WalletPage`의 상단에 `ExchangeRateCard(rate: ...)`를 얹는다. 시간이 없어 Task 8을 자르게 되면, `VisaResultPage`(Task 3) 맨 아래에 `if (trip.visaResult.passportOk) ExchangeRateCard(...)` 한 줄만 추가해도 §6-⑦의 "환율 표시" 부분만은 시연에 넣을 수 있다.

---

### Task 8 (T3 — 여유 시, 가장 먼저 자르는 태스크): 경비 지갑 (drift 로컬 CRUD)

**Files:**
- Create: `app/lib/features/wallet/data/wallet_database.dart`
- Create: `app/lib/features/wallet/widgets/wallet_page.dart`
- Modify: `app/lib/router.dart`
- Modify: `app/lib/features/visa/widgets/visa_result_page.dart`
- Test: `app/test/wallet/wallet_database_test.dart`

**Interfaces:**
- Consumes: Task 7의 `ExchangeRateCard`, `exchangeRateProvider`; Task 3의 `VisaResultPage`
- Produces: `WalletDatabase` (drift) — 테이블 `WalletEntries(id, tripId, category, amountLocal, memo, spentAt)`, `walletDatabaseProvider` (`Provider<WalletDatabase>`)

- [ ] **Step 1: drift 의존성 추가**

```bash
cd app && flutter pub add drift path_provider path sqlite3_flutter_libs
cd app && flutter pub add --dev drift_dev build_runner
```

- [ ] **Step 2: 실패하는 DB 테스트 작성**

`app/test/wallet/wallet_database_test.dart`:

```dart
import 'package:app/features/wallet/data/wallet_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WalletDatabase db;

  setUp(() {
    db = WalletDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('항목을 추가하면 조회된다', () async {
    final id = await db.addEntry(
      tripId: 1,
      category: 'FOOD',
      amountLocal: 150000,
      memo: '쌀국수',
      spentAt: DateTime(2026, 12, 21),
    );

    final entries = await db.entriesForTrip(1);
    expect(entries, hasLength(1));
    expect(entries.first.id, id);
    expect(entries.first.category, 'FOOD');
    expect(entries.first.amountLocal, 150000);
    expect(entries.first.memo, '쌀국수');
  });

  test('여행별로 항목이 분리된다', () async {
    await db.addEntry(
        tripId: 1, category: 'FOOD', amountLocal: 1000, memo: null, spentAt: DateTime(2026, 1, 1));
    await db.addEntry(
        tripId: 2, category: 'FOOD', amountLocal: 2000, memo: null, spentAt: DateTime(2026, 1, 1));

    expect(await db.entriesForTrip(1), hasLength(1));
    expect(await db.entriesForTrip(2), hasLength(1));
  });

  test('삭제하면 목록에서 사라진다', () async {
    final id = await db.addEntry(
        tripId: 1, category: 'ETC', amountLocal: 500, memo: null, spentAt: DateTime(2026, 1, 1));

    await db.deleteEntry(id);

    expect(await db.entriesForTrip(1), isEmpty);
  });

  test('여행별 합계를 계산한다', () async {
    await db.addEntry(
        tripId: 1, category: 'FOOD', amountLocal: 1000, memo: null, spentAt: DateTime(2026, 1, 1));
    await db.addEntry(
        tripId: 1,
        category: 'TRANSPORT',
        amountLocal: 2500,
        memo: null,
        spentAt: DateTime(2026, 1, 2));

    expect(await db.totalForTrip(1), 3500);
  });
}
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd app && flutter test test/wallet/wallet_database_test.dart
```

기대: 컴파일 실패 — `wallet_database.dart`(및 생성될 `wallet_database.g.dart`)를 찾을 수 없음.

- [ ] **Step 4: drift 테이블·데이터베이스 구현**

`app/lib/features/wallet/data/wallet_database.dart`:

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'wallet_database.g.dart';

/// 경비 지갑 — 스펙 §6-⑦, §7: 서버에 저장하지 않는 로컬 전용 테이블이다.
/// 카테고리: FOOD(식비) / TRANSPORT(교통) / LODGING(숙박) / SHOPPING(쇼핑) / ETC(기타)
class WalletEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tripId => integer()();
  TextColumn get category => text()();
  RealColumn get amountLocal => real()();
  TextColumn get memo => text().nullable()();
  DateTimeColumn get spentAt => dateTime()();
}

@DriftDatabase(tables: [WalletEntries])
class WalletDatabase extends _$WalletDatabase {
  WalletDatabase() : super(_openConnection());

  /// 테스트에서 인메모리 DB를 주입하기 위한 생성자.
  WalletDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  Future<int> addEntry({
    required int tripId,
    required String category,
    required double amountLocal,
    required String? memo,
    required DateTime spentAt,
  }) {
    return into(walletEntries).insert(WalletEntriesCompanion.insert(
      tripId: tripId,
      category: category,
      amountLocal: amountLocal,
      memo: Value(memo),
      spentAt: spentAt,
    ));
  }

  Future<List<WalletEntry>> entriesForTrip(int tripId) {
    return (select(walletEntries)
          ..where((t) => t.tripId.equals(tripId))
          ..orderBy([(t) => OrderingTerm.desc(t.spentAt)]))
        .get();
  }

  Future<void> deleteEntry(int id) =>
      (delete(walletEntries)..where((t) => t.id.equals(id))).go();

  Future<double> totalForTrip(int tripId) async {
    final entries = await entriesForTrip(tripId);
    return entries.fold<double>(0, (sum, e) => sum + e.amountLocal);
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'wallet.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

final walletDatabaseProvider = Provider<WalletDatabase>((ref) {
  final db = WalletDatabase();
  ref.onDispose(db.close);
  return db;
});
```

- [ ] **Step 5: 코드 생성 실행**

```bash
cd app && dart run build_runner build --delete-conflicting-outputs
```

기대: `app/lib/features/wallet/data/wallet_database.g.dart`가 생성된다. 이 파일은 자동 생성물이므로 직접 수정하지 않는다.

> **CI/리눅스 환경 참고**: `NativeDatabase.memory()`(테스트에서 사용)는 `package:sqlite3`의 FFI 바인딩이 필요하다. Ubuntu GitHub Actions 러너에는 보통 `libsqlite3-0`가 기본 포함돼 있어 추가 설정 없이 동작하지만, `SqliteException: sqlite3 could not be opened` 류의 오류가 나면 `.github/workflows/ci.yml`의 `app` job에 `- run: sudo apt-get update && sudo apt-get install -y libsqlite3-0` 스텝을 추가한다 (Task 1이 소유한 파일이므로 별도 PR로 조정한다).

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd app && flutter test test/wallet/wallet_database_test.dart
```

기대: 4개 테스트 모두 PASS.

- [ ] **Step 7: 지갑 화면 작성**

`app/lib/features/wallet/widgets/wallet_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../checklist/data/checklist_providers.dart';
import '../data/exchange_rate_api.dart';
import '../data/wallet_database.dart';
import 'exchange_rate_card.dart';

const _categories = {
  'FOOD': '식비',
  'TRANSPORT': '교통',
  'LODGING': '숙박',
  'SHOPPING': '쇼핑',
  'ETC': '기타',
};

class WalletPage extends ConsumerStatefulWidget {
  const WalletPage({super.key, required this.tripId, required this.countryIso2});

  final int tripId;
  final String countryIso2;

  @override
  ConsumerState<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends ConsumerState<WalletPage> {
  Future<List<WalletEntry>>? _entriesFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _entriesFuture = ref.read(walletDatabaseProvider).entriesForTrip(widget.tripId);
    });
  }

  Future<void> _showAddDialog() async {
    var category = 'FOOD';
    final amountController = TextEditingController();
    final memoController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('지출 추가'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: category,
                items: [
                  for (final entry in _categories.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: (v) => setDialogState(() => category = v!),
              ),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '금액 (현지통화)'),
              ),
              TextField(
                controller: memoController,
                decoration: const InputDecoration(labelText: '메모 (선택)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장')),
          ],
        ),
      ),
    );

    final amount = double.tryParse(amountController.text);
    if (saved == true && amount != null) {
      await ref.read(walletDatabaseProvider).addEntry(
            tripId: widget.tripId,
            category: category,
            amountLocal: amount,
            memo: memoController.text.trim().isEmpty ? null : memoController.text.trim(),
            spentAt: DateTime.now(),
          );
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyAsync = ref.watch(countryDetailProvider(widget.countryIso2));

    return Scaffold(
      appBar: AppBar(title: const Text('경비 지갑')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          currencyAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (detail) {
              final code = detail.currencyCode;
              if (code == null) return const SizedBox.shrink();
              final rateAsync = ref.watch(exchangeRateProvider(code));
              return rateAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (rate) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ExchangeRateCard(rate: rate),
                ),
              );
            },
          ),
          FutureBuilder<List<WalletEntry>>(
            future: _entriesFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = snapshot.data!;
              final total = entries.fold<double>(0, (sum, e) => sum + e.amountLocal);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('합계: ${total.toStringAsFixed(0)} (현지통화)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final entry in entries)
                    ListTile(
                      title: Text('${_categories[entry.category] ?? entry.category} · '
                          '${entry.amountLocal.toStringAsFixed(0)}'),
                      subtitle: entry.memo != null ? Text(entry.memo!) : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await ref.read(walletDatabaseProvider).deleteEntry(entry.id);
                          _reload();
                        },
                      ),
                    ),
                  if (entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('기록된 지출이 없습니다')),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 8: 라우팅과 진입 버튼 연결**

`app/lib/router.dart`에 아래를 추가한다. `import` 목록에:

```dart
import 'features/wallet/widgets/wallet_page.dart';
```

`AppRoutes`에 상수를 추가한다.

```dart
  static const wallet = '/visa/wallet';
```

최상위 `routes` 배열(`AppRoutes.visaNew`와 같은 위치)에 추가한다. `WalletPage`는 `tripId`, `countryIso2`를 쿼리 파라미터로 받는다.

```dart
      GoRoute(
        path: AppRoutes.wallet,
        builder: (context, state) => WalletPage(
          tripId: int.parse(state.uri.queryParameters['tripId']!),
          countryIso2: state.uri.queryParameters['iso2']!,
        ),
      ),
```

`app/lib/features/visa/widgets/visa_result_page.dart`의 `ListView`의 `children` 마지막에 지갑 진입 버튼을 추가한다. `Text('역산 준비 일정', ...)` 위, 배지 아래에 아래 블록을 넣는다.

```dart
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () =>
              context.push('/visa/wallet?tripId=${trip.id}&iso2=${trip.countryIso2}'),
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: const Text('경비 지갑 열기'),
        ),
```

이 변경을 넣으려면 `visa_result_page.dart` 상단 import에 `package:go_router/go_router.dart`를 추가해야 한다.

```dart
import 'package:go_router/go_router.dart';
```

- [ ] **Step 9: 전체 검사**

```bash
cd app && flutter analyze && flutter test
```

기대: analyze 무경고, 테스트 전부 PASS.

- [ ] **Step 10: 커밋**

```bash
git add app/lib/features/wallet app/lib/router.dart app/lib/features/visa/widgets/visa_result_page.dart app/test/wallet/wallet_database_test.dart app/pubspec.yaml app/pubspec.lock
git commit -m "feat(app): 경비 지갑 drift 로컬 CRUD (T3)"
```

---

## Self-Review

**스펙 커버리지**

| 스펙 항목 | 담당 Task |
|---|---|
| §6-① 여행계획 입력 → 서버 판정 (`POST /api/trips`) | Task 2 |
| §6-① 무비자/여권잔여요건 배지 | Task 3 |
| §6-① 역산 일정 타임라인 UI | Task 3 |
| §6-① "이미 지난 날짜는 지금 바로 표시" | Task 1(`isPastDue`), Task 3 |
| §6-① `flutter_local_notifications` 로컬 알람, 서버 푸시 아님 | Task 4 |
| §6-② 국가 헤더(플러그/전압/화폐) | Task 6 |
| §6-② 카테고리별 체크박스 + 진행률 | Task 6 |
| §6-⑦ 환율 표시 (한국수출입은행 캐시, KRW↔현지 환산) | Task 7 |
| §6-⑦ 경비 지갑 — drift, 서버 미저장, 카테고리/금액/메모 CRUD + 합계 | Task 8 |
| §6-⑦ 제외 항목(정산/예산경고/영수증OCR) 미구현 확인 | Task 8 — 해당 기능 코드 없음 (설계상 제외) |
| §6-⑦ 환전 알림(D-14 FCM) | **범위 밖으로 명시** — 아래 "이 계획이 다루지 않는 것" 참고 |
| §10 T3 우선순위, 자르는 순서 | Global Constraints + Task 7/8 앞의 경고 문단 |

**이 계획이 다루지 않는 것과 그 이유**

- **환전 알림(스펙 §6-⑦의 "매일 오전 1회 FCM 푸시")은 서버가 트리거하는 배치+FCM 발송이다.** 이는 Spring 스케줄러가 `trip_task`의 "환전" 항목과 D-14 조건을 매일 검사해 FCM을 보내는 로직이므로 **서버(Plan A/R1)의 책임**이며, 이 계획(앱 전용)의 범위 밖이다. 앱 쪽에서 필요한 것은 FCM 수신 초기화뿐인데, 이는 Plan D(채팅, R2)가 채팅 푸시를 위해 이미 `firebase_messaging`을 초기화하므로 별도로 반복하지 않는다. Plan D가 아직 없다면, 이 알림은 시연에서 "서버가 있다면 이렇게 동작한다"는 설명으로 대체할 수 있다.
- **여행 목록 조회(여러 개의 과거/예정 여행을 나열하는 화면)는 만들지 않는다.** 스펙 §7의 API 목록에 `GET /api/trips`(목록)가 없고 `GET /api/trips/{id}`(단건)만 있다. 이 계획은 "활성 여행 1개"만 다루는 것으로 범위를 좁혔다 — 데모 시나리오상 여러 여행을 동시에 준비하는 상황은 스펙에도 없다.

**placeholder 점검**: 각 태스크의 모든 코드 블록은 완성된 구현이며 "TODO"·"나중에 구현" 표기가 없다. 테스트가 실제 값을 assert한다.

**타입 일관성 점검**: `Trip.tasks`(`List<TripTask>`)를 Task 3, 4가 그대로 쓴다. `activeTripIdProvider`/`activeTripProvider`(Task 2)를 Task 3, 6이 동일한 이름으로 참조한다. `ChecklistApi.getChecklist`가 반환하는 `List<ChecklistTemplate>`을 Task 6이 그대로 쓴다. `ExchangeRate.krwFrom`/`localFrom`을 Task 7에서 정의하고 Task 8의 `ExchangeRateCard` 재사용에서 시그니처를 바꾸지 않았다. `WalletDatabase.entriesForTrip`이 반환하는 drift 생성 타입 `WalletEntry`를 Task 8의 `WalletPage`가 그대로 쓴다.

---

## 실행 순서 요약

1. Task 1~6을 순서대로 실행한다 (T1, 필수). Task 3은 Task 4의 `alarm_scheduler.dart`가 있어야 컴파일되므로, Task 3의 코드 작성 후 커밋은 Task 4 완료 시점으로 미룬다(Task 4 Step 10에서 함께 커밋).
2. 시간이 남으면 Task 7, 8을 순서대로 실행한다 (T3).
3. 시간이 부족해지면 **Task 8부터 자르고, 그다음 Task 7을 자른다.** Task 1~6은 절대 자르지 않는다.
