# Plan C — 앱: 2단 지도 + 발걸음 기록 (개인용) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `FootstepsPage`(현재는 빈 화면)를 채워, 사용자가 세계지도에서 방문국을 확인하고 국가를 탭해 날짜별 이동 경로를 보며, 걸음 수집(백그라운드 자동/포그라운드 수동/Timeline 임포트) 3종과 Health Connect 걸음 수를 로컬 drift DB에 캐시한 뒤 서버와 동기화한다.

**Architecture:** `geolocator`로 좌표를 얻고 `geocoding`으로 국가(ISO-2)를 역지오코딩해 drift 테이블 `checkins`/`daily_steps`에 저장한다. 수집 경로는 3개(WorkManager 1시간 주기 자동, 포그라운드 수동 버튼, Google Timeline 내보내기 JSON 임포트)지만 모두 같은 `FootstepsRepository`를 거쳐 같은 로컬 스키마에 쌓이므로 지도·동기화 로직은 수집 방식을 몰라도 된다. `health` 패키지로 Health Connect에서 일별 걸음 수를 읽어, 그 날짜에 가장 많이 체크인된 국가에 귀속시킨다. 동기화 서비스가 `synced=false`인 로우를 골라 서버에 배치 전송한다. 지도는 상위(세계지도 choropleth)와 하위(국가별 점선 경로)로 나뉘며 `FootstepsPage` 안에서 로컬 상태로 전환한다(go_router 라우트 추가 없음).

**Tech Stack:** Flutter 3.x / Riverpod (Phase 0에서 확립) · `google_maps_flutter`, `geolocator`, `geocoding`, `permission_handler`, `workmanager`, `health`, `file_picker`, `drift`(SQLite) · dio (`apiClientProvider`, Phase 0 Task 9)

**Spec:** `docs/superpowers/specs/2026-09-06-overseas-travel-app-design.md` §6-③, §7 (`checkin`, `daily_steps`)

## Global Constraints

- **모노레포 구조**: 앱 코드는 전부 `app/` 아래. `app/lib/features/footsteps/`에 이 계획의 코드를 둔다.
- **Android 전용.** iOS 관련 설정은 손대지 않는다.
- **비밀정보를 커밋하지 않는다.** Maps API 키는 `app/android/app/src/main/AndroidManifest.xml`에서 `${MAPS_ANDROID_API_KEY}` 플레이스홀더로 참조하고 실제 값은 `app/android/local.properties`(이미 `.gitignore` 대상)에 둔다.
- **브랜치 전략**: `feature/*` → `develop`, PR 2인 승인. 매주 금요일 `develop` 머지.
- **인증 추상화 규칙**: 서버 호출은 전부 `apiClientProvider`(Phase 0 Task 9가 만든 `Provider<Dio>`, Firebase ID Token 인터셉터 내장)를 재사용한다. 이 계획에서 dio를 새로 만들지 않는다.
- **패키지 루트**: `com.travelfootsteps`
- **서버 연결**: 안드로이드 에뮬레이터 베이스 URL은 `http://10.0.2.2:8080` (Phase 0 `resolveBaseUrl`이 이미 처리).
- **1시간 간격**: 백그라운드 자동 체크인은 정확히 1시간이 아니라 "대략 1시간"이면 충분하다(Doze 모드 지연은 무해함, 스펙 §6-③). 5초/초 단위 고빈도 추적은 만들지 않는다 — 그룹원 실시간 위치공유(5초 STOMP)는 Plan D 소관이며 이 계획과 무관하다.
- **Google Timeline API는 존재하지 않는다.** 서버·서드파티가 Google 계정의 Timeline을 프로그래매틱하게 읽을 방법이 없으므로, 사용자가 직접 내보낸 JSON 파일을 `file_picker`로 받아 파싱하는 것만 구현한다.
- **백업 경로 (스펙 §10 리스크 대응)**: 백그라운드 추적이 기기별로 죽는 것은 이미 알려진 리스크다. 포그라운드 수동 체크인과 Timeline 임포트가 완전히 동작해야 그 백업이 실질적이다 — 이 계획에서 이 둘을 백그라운드 자동 추적과 **동등한 우선순위**로 구현한다(Task 순서상 오히려 먼저 만든다).
- **재사용 힌트 (Plan F 대비)**: 지도 위젯(`WorldMapPage`, `CountryDetailMapPage` 내부의 지도 컴포넌트)은 Plan F(주변 여행 정보, R3, W9~10)가 Places 마커를 얹어 재사용할 수 있으므로, 지도 초기화·카메라 이동 로직은 별도 위젯(`lib/features/footsteps/map/base_google_map.dart`)으로 분리해 둔다.
- **실기기 검증 표시**: 각 Task의 Step에는 `[실기기 필요]` 또는 `[단위 테스트로 검증 가능]` 태그를 붙인다. WorkManager 백그라운드 실행과 Health Connect 권한 플로우는 에뮬레이터/CI에서 재현되지 않으므로 실기기 필요로 표시하고, 그 안의 순수 로직(파서·DB 저장·귀속 계산)은 분리해 단위 테스트로 검증한다.

---

## File Structure

```
app/
├── pubspec.yaml                                          Modify: 신규 패키지 추가
├── android/app/src/main/AndroidManifest.xml               Modify: 위치 권한, Maps 키, WorkManager
├── assets/geo/world_countries.geojson                     Create: 국가 경계 폴리곤 (Task 7)
├── lib/
│   ├── core/
│   │   └── db/
│   │       └── app_database.dart                          Create: drift 로컬 DB 정의 (Task 1)
│   │       └── app_database.g.dart                        Generate: build_runner 산출물
│   └── features/footsteps/
│       ├── footsteps_page.dart                            Modify: 상위/하위 지도 전환 셸 (Task 8)
│       ├── data/
│       │   ├── checkin.dart                                Create: Checkin 도메인 모델 (Task 1)
│       │   ├── daily_step.dart                             Create: DailyStep 도메인 모델 (Task 1)
│       │   ├── country_resolver.dart                       Create: 좌표→ISO-2 추상화 (Task 2)
│       │   ├── geocoding_country_resolver.dart             Create: geocoding 구현체 (Task 2)
│       │   ├── footsteps_repository.dart                   Create: 로컬 DB + 수집 3종 통합 (Task 2, 3, 5)
│       │   ├── footsteps_api.dart                          Create: 서버 동기화 dio 클라이언트 (Task 6)
│       │   └── footsteps_sync_service.dart                 Create: 미동기화 로우 push (Task 6)
│       ├── background/
│       │   ├── footstep_task_handler.dart                  Create: WorkManager 콜백의 순수 로직 (Task 3)
│       │   ├── footstep_workmanager.dart                   Create: WorkManager 등록/디스패처 (Task 3)
│       │   └── battery_optimization.dart                   Create: 배터리 최적화 예외 요청 플로우 (Task 3)
│       ├── health/
│       │   ├── health_steps_service.dart                   Create: Health Connect 래퍼 (Task 4)
│       │   └── step_attribution.dart                       Create: 걸음수→국가 귀속 순수 함수 (Task 4)
│       ├── import/
│       │   ├── timeline_import_parser.dart                 Create: Timeline JSON 파서 (Task 5)
│       │   └── timeline_import_page.dart                   Create: file_picker UI (Task 5)
│       ├── map/
│       │   ├── base_google_map.dart                        Create: 재사용 가능한 지도 셸 (Task 7)
│       │   ├── world_geojson_parser.dart                   Create: GeoJSON 파싱 (Task 7)
│       │   ├── world_map_page.dart                         Create: 상위 지도 (Task 7)
│       │   └── country_detail_map_page.dart                Create: 하위 지도 (Task 8)
│       └── providers/
│           └── footsteps_providers.dart                    Create: Riverpod provider 모음 (Task 2, 4, 6, 7, 8)
└── test/
    ├── db/app_database_test.dart                           Create (Task 1)
    ├── footsteps/
    │   ├── country_resolver_test.dart                       Create (Task 2)
    │   ├── footsteps_repository_test.dart                   Create (Task 2, 5)
    │   ├── footstep_task_handler_test.dart                  Create (Task 3)
    │   ├── step_attribution_test.dart                       Create (Task 4)
    │   ├── timeline_import_parser_test.dart                 Create (Task 5)
    │   ├── footsteps_sync_service_test.dart                 Create (Task 6)
    │   └── world_geojson_parser_test.dart                   Create (Task 7)
    └── fixtures/
        └── timeline_export_sample.json                      Create (Task 5)
```

**분리 원칙**: `background/footstep_task_handler.dart`는 WorkManager의 top-level 콜백(`callbackDispatcher`, isolate 엔트리포인트라 테스트 러너가 직접 부를 수 없음)과 실제 판단 로직을 분리한다 — 콜백은 `handleFootstepTask(FootstepsRepository, CountryResolver, DateTime)`을 호출하기만 하고, 그 함수만 단위 테스트한다. `health/step_attribution.dart`도 같은 이유로 Health Connect API 호출과 "이 날짜엔 어느 나라에 귀속시키나" 판단을 분리한다.

---

### Task 1: drift 로컬 DB — `checkins`, `daily_steps` 테이블

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `.github/workflows/ci.yml`
- Create: `app/lib/core/db/app_database.dart`
- Create: `app/lib/features/footsteps/data/checkin.dart`
- Create: `app/lib/features/footsteps/data/daily_step.dart`
- Test: `app/test/db/app_database_test.dart`

**Interfaces:**
- Consumes: 없음 (이 계획의 첫 태스크)
- Produces:
  - `AppDatabase` (drift `GeneratedDatabase` 하위 클래스) — `insertCheckin(CheckinsCompanion)`, `allCheckins()`, `checkinsForCountry(String iso)`, `unsyncedCheckins()`, `markCheckinSynced(int id, String serverId)`, `upsertDailySteps(DateTime date, String iso, int count)`, `unsyncedDailySteps()`, `markDailyStepsSynced(int id, String serverId)`, `cumulativeStepsByCountry()` → `Future<Map<String,int>>`
  - `Checkin`, `DailyStep` (도메인 모델, drift row가 아닌 순수 Dart 클래스 — UI·다른 계층이 drift 타입에 의존하지 않게 한다)
  - `CheckinSource` enum: `auto`, `manual`, `import`
  - `appDatabaseProvider` (Riverpod `Provider<AppDatabase>`) — Task 2 이후 전부가 이걸 통해 DB에 접근한다. **주의**: 이후 다른 계획(Plan B의 `wallet_entry` 등)도 같은 `AppDatabase`에 테이블을 추가할 수 있으므로, 이 태스크는 `AppDatabase`를 앱 전역의 단일 drift DB로 취급한다.

> **왜 로컬 전용 도메인 모델을 따로 두는가**: drift는 `@DriftDatabase` 어노테이션으로 `Checkin` 같은 이름의 row 클래스를 자동 생성한다. 이름이 겹치면 혼란스러우므로, drift가 생성하는 로우 타입은 `CheckinRow`로 별칭 처리하고 `data/checkin.dart`의 `Checkin`이 앱 전체가 실제로 사용하는 타입이 되게 한다.

- [ ] **Step 1: 패키지 추가** `[단위 테스트로 검증 가능]`

```bash
cd app
flutter pub add drift path_provider path sqlite3_flutter_libs
flutter pub add geolocator geocoding permission_handler
flutter pub add workmanager health file_picker google_maps_flutter
flutter pub add dev:drift_dev dev:build_runner
```

`pubspec.yaml`의 `flutter:` 섹션에 GeoJSON 에셋 등록을 미리 추가해 둔다(Task 7에서 파일을 채운다).

```yaml
flutter:
  assets:
    - assets/geo/world_countries.geojson
```

- [ ] **Step 2: CI에 sqlite3 네이티브 라이브러리 설치 단계 추가**

`.github/workflows/ci.yml`의 `app` job, `flutter pub get` 다음 줄에 추가한다. drift 테스트가 `NativeDatabase.memory()`로 실제 SQLite를 열기 때문에 Ubuntu 러너에 헤더가 없으면 실패한다.

```yaml
      - run: flutter pub get
      - run: sudo apt-get update && sudo apt-get install -y libsqlite3-dev
      - run: flutter analyze
      - run: flutter test
```

- [ ] **Step 3: 도메인 모델 작성**

`app/lib/features/footsteps/data/checkin.dart`:

```dart
enum CheckinSource { auto, manual, import }

class Checkin {
  const Checkin({
    required this.id,
    required this.lat,
    required this.lng,
    required this.countryIso,
    required this.recordedAt,
    required this.source,
    required this.synced,
    this.serverId,
  });

  final int id;
  final double lat;
  final double lng;

  /// ISO-3166-1 alpha-2. 역지오코딩에 실패하면 'XX'(미확인)로 저장하고
  /// 동기화 시 재시도 대상이 된다.
  final String countryIso;
  final DateTime recordedAt;
  final CheckinSource source;
  final bool synced;
  final String? serverId;

  static const unknownCountry = 'XX';
}
```

`app/lib/features/footsteps/data/daily_step.dart`:

```dart
class DailyStep {
  const DailyStep({
    required this.id,
    required this.date,
    required this.countryIso,
    required this.stepCount,
    required this.synced,
    this.serverId,
  });

  final int id;

  /// 자정(00:00) 기준 날짜. 시간 정보는 버린다.
  final DateTime date;
  final String countryIso;
  final int stepCount;
  final bool synced;
  final String? serverId;
}
```

- [ ] **Step 4: 실패하는 DB 테스트 작성**

`app/test/db/app_database_test.dart`:

```dart
import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('체크인을 저장하고 전체 조회하면 그대로 나온다', () async {
    await db.insertCheckin(lat: 35.6, lng: 139.7, countryIso: 'JP',
        recordedAt: DateTime.utc(2026, 12, 20, 9), source: CheckinSource.manual);

    final all = await db.allCheckins();

    expect(all, hasLength(1));
    expect(all.first.countryIso, 'JP');
    expect(all.first.source, CheckinSource.manual);
    expect(all.first.synced, isFalse);
  });

  test('국가별로 필터링해 조회할 수 있다', () async {
    await db.insertCheckin(lat: 35.6, lng: 139.7, countryIso: 'JP',
        recordedAt: DateTime.utc(2026, 12, 20, 9), source: CheckinSource.auto);
    await db.insertCheckin(lat: 21.0, lng: 105.8, countryIso: 'VN',
        recordedAt: DateTime.utc(2026, 12, 21, 9), source: CheckinSource.auto);

    final jp = await db.checkinsForCountry('JP');

    expect(jp, hasLength(1));
    expect(jp.first.countryIso, 'JP');
  });

  test('동기화되지 않은 체크인만 조회하고, 동기화 표시 후에는 빠진다', () async {
    final id = await db.insertCheckin(lat: 35.6, lng: 139.7, countryIso: 'JP',
        recordedAt: DateTime.utc(2026, 12, 20, 9), source: CheckinSource.auto);

    expect(await db.unsyncedCheckins(), hasLength(1));

    await db.markCheckinSynced(id, 'server-id-1');

    expect(await db.unsyncedCheckins(), isEmpty);
  });

  test('같은 날짜·국가의 걸음 수는 upsert된다', () async {
    final date = DateTime.utc(2026, 12, 20);

    await db.upsertDailySteps(date, 'JP', 5000);
    await db.upsertDailySteps(date, 'JP', 7000);

    final rows = await db.allDailySteps();
    expect(rows, hasLength(1));
    expect(rows.first.stepCount, 7000);
    expect(rows.first.synced, isFalse); // 값이 바뀌었으니 재동기화 대상
  });

  test('국가별 누적 걸음 수를 집계한다', () async {
    await db.upsertDailySteps(DateTime.utc(2026, 12, 20), 'JP', 5000);
    await db.upsertDailySteps(DateTime.utc(2026, 12, 21), 'JP', 6000);
    await db.upsertDailySteps(DateTime.utc(2026, 12, 22), 'VN', 3000);

    final totals = await db.cumulativeStepsByCountry();

    expect(totals['JP'], 11000);
    expect(totals['VN'], 3000);
  });
}
```

- [ ] **Step 5: 테스트 실패 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/db/app_database_test.dart
```

기대: 컴파일 실패 — `app/core/db/app_database.dart`를 찾을 수 없음.

- [ ] **Step 6: drift 스키마 구현**

`app/lib/core/db/app_database.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/footsteps/data/checkin.dart' as domain;
import '../../features/footsteps/data/daily_step.dart' as domain;

part 'app_database.g.dart';

@DataClassName('CheckinRow')
class Checkins extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  TextColumn get countryIso => text().withLength(min: 2, max: 2)();
  DateTimeColumn get recordedAt => dateTime()();
  TextColumn get source => textEnum<domain.CheckinSource>()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  TextColumn get serverId => text().nullable()();
}

@DataClassName('DailyStepRow')
class DailySteps extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  TextColumn get countryIso => text().withLength(min: 2, max: 2)();
  IntColumn get stepCount => integer()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  TextColumn get serverId => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {date, countryIso}
      ];
}

@DriftDatabase(tables: [Checkins, DailySteps])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 테스트에서 인메모리 DB를 주입하기 위한 생성자.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  Future<int> insertCheckin({
    required double lat,
    required double lng,
    required String countryIso,
    required DateTime recordedAt,
    required domain.CheckinSource source,
  }) {
    return into(checkins).insert(CheckinsCompanion.insert(
      lat: lat,
      lng: lng,
      countryIso: countryIso,
      recordedAt: recordedAt,
      source: source,
    ));
  }

  Future<List<domain.Checkin>> allCheckins() async {
    final rows = await select(checkins).get();
    return rows.map(_toDomainCheckin).toList();
  }

  Future<List<domain.Checkin>> checkinsForCountry(String iso) async {
    final rows = await (select(checkins)
          ..where((t) => t.countryIso.equals(iso))
          ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)]))
        .get();
    return rows.map(_toDomainCheckin).toList();
  }

  Future<List<domain.Checkin>> unsyncedCheckins() async {
    final rows =
        await (select(checkins)..where((t) => t.synced.equals(false))).get();
    return rows.map(_toDomainCheckin).toList();
  }

  Future<void> markCheckinSynced(int id, String serverId) {
    return (update(checkins)..where((t) => t.id.equals(id))).write(
      CheckinsCompanion(synced: const Value(true), serverId: Value(serverId)),
    );
  }

  Future<void> upsertDailySteps(DateTime date, String countryIso, int stepCount) {
    return into(dailySteps).insertOnConflictUpdate(DailyStepsCompanion.insert(
      date: date,
      countryIso: countryIso,
      stepCount: stepCount,
      synced: const Value(false),
    ));
  }

  Future<List<domain.DailyStep>> allDailySteps() async {
    final rows = await select(dailySteps).get();
    return rows.map(_toDomainDailyStep).toList();
  }

  Future<List<domain.DailyStep>> unsyncedDailySteps() async {
    final rows = await (select(dailySteps)..where((t) => t.synced.equals(false)))
        .get();
    return rows.map(_toDomainDailyStep).toList();
  }

  Future<void> markDailyStepsSynced(int id, String serverId) {
    return (update(dailySteps)..where((t) => t.id.equals(id))).write(
      DailyStepsCompanion(synced: const Value(true), serverId: Value(serverId)),
    );
  }

  Future<Map<String, int>> cumulativeStepsByCountry() async {
    final rows = await allDailySteps();
    final totals = <String, int>{};
    for (final row in rows) {
      totals.update(row.countryIso, (v) => v + row.stepCount,
          ifAbsent: () => row.stepCount);
    }
    return totals;
  }

  domain.Checkin _toDomainCheckin(CheckinRow row) => domain.Checkin(
        id: row.id,
        lat: row.lat,
        lng: row.lng,
        countryIso: row.countryIso,
        recordedAt: row.recordedAt,
        source: row.source,
        synced: row.synced,
        serverId: row.serverId,
      );

  domain.DailyStep _toDomainDailyStep(DailyStepRow row) => domain.DailyStep(
        id: row.id,
        date: row.date,
        countryIso: row.countryIso,
        stepCount: row.stepCount,
        synced: row.synced,
        serverId: row.serverId,
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = p.join(dbFolder.path, 'travelfootsteps.sqlite');
    return NativeDatabase.createInBackground(File(file) as dynamic);
  });
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
```

> `_openConnection`의 `File(...)`은 `dart:io`의 `File`이다. 실제 구현 시 파일 상단에 `import 'dart:io';`를 추가한다 — 위 스니펫은 지면상 생략했다.

- [ ] **Step 7: 코드 생성**

```bash
cd app && dart run build_runner build --delete-conflicting-outputs
```

기대: `app/lib/core/db/app_database.g.dart` 생성.

- [ ] **Step 8: 테스트 통과 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/db/app_database_test.dart
```

기대: 5개 테스트 모두 PASS.

- [ ] **Step 9: 커밋**

```bash
git add app/pubspec.yaml app/pubspec.lock .github/workflows/ci.yml \
  app/lib/core/db app/lib/features/footsteps/data/checkin.dart \
  app/lib/features/footsteps/data/daily_step.dart app/test/db
git commit -m "feat(app): 발걸음 로컬 drift DB (checkins, daily_steps)"
```

---

### Task 2: 국가 판정 + 포그라운드 수동 체크인 ("여기 저장")

**Files:**
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Create: `app/lib/features/footsteps/data/country_resolver.dart`
- Create: `app/lib/features/footsteps/data/geocoding_country_resolver.dart`
- Create: `app/lib/features/footsteps/data/footsteps_repository.dart`
- Create: `app/lib/features/footsteps/providers/footsteps_providers.dart`
- Test: `app/test/footsteps/country_resolver_test.dart`
- Test: `app/test/footsteps/footsteps_repository_test.dart`

**Interfaces:**
- Consumes: Task 1의 `AppDatabase.insertCheckin`, `appDatabaseProvider`
- Produces:
  - `abstract class CountryResolver { Future<String> resolveIso2(double lat, double lng); }` — 실패 시 `Checkin.unknownCountry`('XX')를 반환한다(예외를 던지지 않는다). Task 3(백그라운드), Task 5(임포트)가 재사용한다.
  - `class FootstepsRepository { Future<void> recordManualCheckin(); Future<void> recordCheckinAt(double lat, double lng, DateTime at, CheckinSource source); Future<List<Checkin>> allCheckins(); Future<List<Checkin>> checkinsForCountry(String iso); Future<Map<String,int>> cumulativeStepsByCountry(); }` — Task 3, 4, 5, 7, 8이 전부 이 repository를 통해서만 DB·위치·국가판정에 접근한다.
  - `footstepsRepositoryProvider` (`Provider<FootstepsRepository>`), `countryResolverProvider` (`Provider<CountryResolver>`)

> **왜 `CountryResolver`를 인터페이스로 분리하는가**: `geocoding` 패키지는 네트워크·플랫폼 채널을 타므로 위젯 테스트/유닛 테스트에서 직접 호출할 수 없다. 이 경계가 없으면 Task 3(WorkManager)과 Task 5(Timeline 임포트)의 로직을 단위 테스트할 방법이 없어진다.

- [ ] **Step 1: 매니페스트에 위치 권한 추가**

`app/android/app/src/main/AndroidManifest.xml`의 `<manifest>` 태그 안, `<application>` 앞에 추가한다.

```xml
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
    <uses-permission android:name="android.permission.INTERNET" />
```

`ACCESS_BACKGROUND_LOCATION`은 Task 3의 WorkManager 주기 작업이 앱이 백그라운드에 있을 때도 좌표를 읽기 위해 필요하다.

- [ ] **Step 2: 실패하는 `CountryResolver` 인터페이스 테스트 작성**

`app/test/footsteps/country_resolver_test.dart`:

```dart
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCountryResolver implements CountryResolver {
  _FakeCountryResolver(this._mapping);
  final Map<String, String> _mapping; // 'lat,lng' -> iso2

  @override
  Future<String> resolveIso2(double lat, double lng) async {
    return _mapping['$lat,$lng'] ?? Checkin.unknownCountry;
  }
}

void main() {
  test('등록된 좌표는 매핑된 국가 코드를 반환한다', () async {
    final resolver = _FakeCountryResolver({'35.6,139.7': 'JP'});

    expect(await resolver.resolveIso2(35.6, 139.7), 'JP');
  });

  test('매핑에 없는 좌표는 미확인(XX)을 반환한다', () async {
    final resolver = _FakeCountryResolver({});

    expect(await resolver.resolveIso2(0, 0), Checkin.unknownCountry);
  });
}
```

이 테스트는 인터페이스 계약(실패해도 예외 대신 'XX')을 회귀로 지키는 용도다. `CountryResolver`가 아직 없으므로 컴파일이 실패한다.

- [ ] **Step 3: 테스트 실패 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/country_resolver_test.dart
```

기대: 컴파일 실패 — `country_resolver.dart`를 찾을 수 없음.

- [ ] **Step 4: 인터페이스와 실제 구현체 작성**

`app/lib/features/footsteps/data/country_resolver.dart`:

```dart
abstract class CountryResolver {
  /// 좌표를 ISO-3166-1 alpha-2 국가 코드로 변환한다.
  /// 실패(오프라인, 바다 위 좌표 등)해도 예외를 던지지 않고 'XX'를 반환한다.
  Future<String> resolveIso2(double lat, double lng);
}
```

`app/lib/features/footsteps/data/geocoding_country_resolver.dart`:

```dart
import 'package:geocoding/geocoding.dart';

import 'checkin.dart';
import 'country_resolver.dart';

class GeocodingCountryResolver implements CountryResolver {
  @override
  Future<String> resolveIso2(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      final iso = placemarks.firstOrNull?.isoCountryCode;
      if (iso == null || iso.length != 2) return Checkin.unknownCountry;
      return iso.toUpperCase();
    } catch (_) {
      return Checkin.unknownCountry;
    }
  }
}

extension on List<Placemark> {
  Placemark? get firstOrNull => isEmpty ? null : first;
}
```

- [ ] **Step 5: 테스트 통과 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/country_resolver_test.dart
```

기대: 2개 테스트 모두 PASS.

- [ ] **Step 6: 실패하는 repository 테스트 작성**

`app/test/footsteps/footsteps_repository_test.dart`:

```dart
import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:app/features/footsteps/data/footsteps_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedCountryResolver implements CountryResolver {
  _FixedCountryResolver(this.iso);
  final String iso;

  @override
  Future<String> resolveIso2(double lat, double lng) async => iso;
}

class _FixedLocation {
  const _FixedLocation(this.lat, this.lng);
  final double lat;
  final double lng;
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('좌표를 주면 국가를 판정해 저장한다', () async {
    final repo = FootstepsRepository(db: db, countryResolver: _FixedCountryResolver('VN'));

    await repo.recordCheckinAt(21.0, 105.8, DateTime.utc(2026, 12, 21, 10), CheckinSource.manual);

    final all = await repo.allCheckins();
    expect(all, hasLength(1));
    expect(all.first.countryIso, 'VN');
    expect(all.first.source, CheckinSource.manual);
  });

  test('국가별 조회와 누적 걸음수 집계를 그대로 위임한다', () async {
    final repo = FootstepsRepository(db: db, countryResolver: _FixedCountryResolver('JP'));
    await repo.recordCheckinAt(35.6, 139.7, DateTime.utc(2026, 12, 20, 9), CheckinSource.auto);

    final jp = await repo.checkinsForCountry('JP');
    expect(jp, hasLength(1));

    await db.upsertDailySteps(DateTime.utc(2026, 12, 20), 'JP', 4000);
    final totals = await repo.cumulativeStepsByCountry();
    expect(totals['JP'], 4000);
  });
}
```

- [ ] **Step 7: 테스트 실패 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/footsteps_repository_test.dart
```

기대: 컴파일 실패 — `footsteps_repository.dart`를 찾을 수 없음.

- [ ] **Step 8: `FootstepsRepository` 구현 (위치 조회 포함)**

`app/lib/features/footsteps/data/footsteps_repository.dart`:

```dart
import 'package:geolocator/geolocator.dart';

import '../../../core/db/app_database.dart';
import 'checkin.dart';
import 'country_resolver.dart';
import 'daily_step.dart';

class FootstepsRepository {
  FootstepsRepository({required AppDatabase db, required CountryResolver countryResolver})
      : _db = db,
        _countryResolver = countryResolver;

  final AppDatabase _db;
  final CountryResolver _countryResolver;

  /// "여기 저장" 버튼. 위치 권한을 확인·요청하고 현재 좌표를 기록한다.
  Future<void> recordManualCheckin() async {
    final position = await _ensureLocationAndGetPosition();
    await recordCheckinAt(
      position.latitude,
      position.longitude,
      DateTime.now().toUtc(),
      CheckinSource.manual,
    );
  }

  /// 좌표가 이미 있는 경우(WorkManager, Timeline 임포트)의 공통 저장 경로.
  Future<void> recordCheckinAt(
    double lat,
    double lng,
    DateTime at,
    CheckinSource source,
  ) async {
    final iso = await _countryResolver.resolveIso2(lat, lng);
    await _db.insertCheckin(
      lat: lat,
      lng: lng,
      countryIso: iso,
      recordedAt: at,
      source: source,
    );
  }

  Future<List<Checkin>> allCheckins() => _db.allCheckins();

  Future<List<Checkin>> checkinsForCountry(String iso) => _db.checkinsForCountry(iso);

  Future<Map<String, int>> cumulativeStepsByCountry() => _db.cumulativeStepsByCountry();

  Future<List<Checkin>> unsyncedCheckins() => _db.unsyncedCheckins();

  Future<void> markCheckinSynced(int id, String serverId) => _db.markCheckinSynced(id, serverId);

  Future<List<DailyStep>> unsyncedDailySteps() => _db.unsyncedDailySteps();

  Future<void> markDailyStepsSynced(int id, String serverId) =>
      _db.markDailyStepsSynced(id, serverId);

  Future<void> upsertDailySteps(DateTime date, String iso, int stepCount) =>
      _db.upsertDailySteps(date, iso, stepCount);

  Future<Position> _ensureLocationAndGetPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('위치 권한이 거부되었습니다. 설정에서 허용해 주세요.');
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('위치 서비스(GPS)가 꺼져 있습니다.');
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    );
  }
}
```

- [ ] **Step 9: 테스트 통과 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/footsteps_repository_test.dart
```

기대: 2개 테스트 모두 PASS.

- [ ] **Step 10: Riverpod provider 배선**

`app/lib/features/footsteps/providers/footsteps_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../data/country_resolver.dart';
import '../data/footsteps_repository.dart';
import '../data/geocoding_country_resolver.dart';

final countryResolverProvider = Provider<CountryResolver>((ref) => GeocodingCountryResolver());

final footstepsRepositoryProvider = Provider<FootstepsRepository>((ref) {
  return FootstepsRepository(
    db: ref.watch(appDatabaseProvider),
    countryResolver: ref.watch(countryResolverProvider),
  );
});
```

- [ ] **Step 11: 커밋**

```bash
git add app/android/app/src/main/AndroidManifest.xml \
  app/lib/features/footsteps/data app/lib/features/footsteps/providers \
  app/test/footsteps/country_resolver_test.dart app/test/footsteps/footsteps_repository_test.dart
git commit -m "feat(app): 국가 판정과 포그라운드 수동 체크인"
```

- [ ] **Step 12: 실기기 검증 — "여기 저장" 버튼 임시 배선** `[실기기 필요]`

`FootstepsPage`는 Task 8에서 최종 UI로 교체되지만, 이 시점에 실기기에서 권한 플로우를 확인해야 한다. 임시로 `footsteps_page.dart`에 버튼 하나를 붙여 실행한다.

```dart
FilledButton(
  onPressed: () => ref.read(footstepsRepositoryProvider).recordManualCheckin(),
  child: const Text('여기 저장 (임시 테스트용)'),
)
```

실기기(에뮬레이터는 GPS 모의값만 주므로 가능하면 실기기)에서 버튼을 눌러 위치 권한 다이얼로그가 뜨는지, 허용 후 앱을 재시작 없이 체크인이 쌓이는지 확인한다. 확인 후 이 임시 코드는 Task 8에서 제거된다.

---

### Task 3: WorkManager 백그라운드 자동 체크인 (1시간 주기) + 배터리 최적화 예외

**Files:**
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Modify: `app/lib/main.dart`
- Create: `app/lib/features/footsteps/background/footstep_task_handler.dart`
- Create: `app/lib/features/footsteps/background/footstep_workmanager.dart`
- Create: `app/lib/features/footsteps/background/battery_optimization.dart`
- Test: `app/test/footsteps/footstep_task_handler_test.dart`

**Interfaces:**
- Consumes: Task 2의 `FootstepsRepository.recordCheckinAt`, `CountryResolver`
- Produces:
  - `Future<void> handleFootstepTask({required FootstepsRepository repository, required Future<Position> Function() getCurrentPosition})` — WorkManager 콜백이 호출하는 순수 로직. 좌표 취득 실패(권한 없음, GPS 꺼짐)를 흡수하고 예외를 던지지 않는다(재시도는 다음 주기가 알아서 한다).
  - `void registerFootstepBackgroundTask()` — 앱 시작 시 1회 호출. `main.dart`가 호출한다.
  - `Future<bool> requestIgnoreBatteryOptimization()` — 최초 실행 시 1회 요청.

> **왜 실제 동작 검증이 어려운가**: WorkManager 최소 주기는 15분이며 안드로이드가 정확한 시각을 보장하지 않는다. 에뮬레이터/CI에서 "1시간 뒤 실행됨"을 자동 검증할 수 없다. 이 태스크는 **등록 로직**과 **콜백 안의 판단 로직**만 단위 테스트하고, 실제 주기 실행은 실기기에서 배터리를 소모해 가며 관찰한다.

- [ ] **Step 1: 매니페스트에 WorkManager 관련 권한 추가**

`app/android/app/src/main/AndroidManifest.xml`에 Task 2에서 추가한 권한 아래에 추가한다.

```xml
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

`RECEIVE_BOOT_COMPLETED`는 기기 재부팅 후에도 WorkManager 주기 작업이 재등록되게 하기 위함이다(`workmanager` 패키지가 내부적으로 사용).

- [ ] **Step 2: 실패하는 핸들러 테스트 작성**

`app/test/footsteps/footstep_task_handler_test.dart`:

```dart
import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/background/footstep_task_handler.dart';
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:app/features/footsteps/data/footsteps_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class _FixedCountryResolver implements CountryResolver {
  @override
  Future<String> resolveIso2(double lat, double lng) async => 'JP';
}

Position _fakePosition(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  late AppDatabase db;
  late FootstepsRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FootstepsRepository(db: db, countryResolver: _FixedCountryResolver());
  });

  tearDown(() => db.close());

  test('좌표를 얻으면 AUTO 소스로 체크인을 저장한다', () async {
    await handleFootstepTask(
      repository: repo,
      getCurrentPosition: () async => _fakePosition(35.6, 139.7),
    );

    final all = await repo.allCheckins();
    expect(all, hasLength(1));
    expect(all.first.source, CheckinSource.auto);
    expect(all.first.countryIso, 'JP');
  });

  test('위치를 얻지 못해도 예외를 밖으로 던지지 않는다', () async {
    await handleFootstepTask(
      repository: repo,
      getCurrentPosition: () async => throw StateError('위치 서비스 꺼짐'),
    );

    expect(await repo.allCheckins(), isEmpty);
  });
}
```

- [ ] **Step 3: 테스트 실패 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/footstep_task_handler_test.dart
```

기대: 컴파일 실패 — `footstep_task_handler.dart`를 찾을 수 없음.

- [ ] **Step 4: 핸들러 구현**

`app/lib/features/footsteps/background/footstep_task_handler.dart`:

```dart
import 'package:geolocator/geolocator.dart';

import '../data/checkin.dart';
import '../data/footsteps_repository.dart';

/// WorkManager 콜백의 실제 판단 로직. isolate 엔트리포인트에서 분리해
/// 단위 테스트가 가능하게 한다.
Future<void> handleFootstepTask({
  required FootstepsRepository repository,
  required Future<Position> Function() getCurrentPosition,
}) async {
  try {
    final position = await getCurrentPosition();
    await repository.recordCheckinAt(
      position.latitude,
      position.longitude,
      DateTime.now().toUtc(),
      CheckinSource.auto,
    );
  } catch (_) {
    // 권한 거부, GPS 꺼짐, 오프라인 등. 다음 1시간 주기가 다시 시도하므로
    // 여기서 재시도하지 않는다 — WorkManager에 실패로 보고하면 짧은
    // 백오프로 재시도가 몰려 배터리를 더 쓰게 된다.
  }
}
```

- [ ] **Step 5: 테스트 통과 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/footstep_task_handler_test.dart
```

기대: 2개 테스트 모두 PASS.

- [ ] **Step 6: WorkManager 등록/디스패처 작성** `[실기기 필요]`

`app/lib/features/footsteps/background/footstep_workmanager.dart`:

```dart
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/db/app_database.dart';
import '../data/geocoding_country_resolver.dart';
import '../data/footsteps_repository.dart';
import 'footstep_task_handler.dart';

const footstepTaskName = 'com.travelfootsteps.footstepCheckin';

/// WorkManager가 별도 isolate에서 호출하는 top-level 콜백.
/// Riverpod 컨테이너에 접근할 수 없으므로 의존성을 직접 만든다.
@pragma('vm:entry-point')
void footstepCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != footstepTaskName) return true;

    final db = AppDatabase();
    final repository = FootstepsRepository(
      db: db,
      countryResolver: GeocodingCountryResolver(),
    );

    await handleFootstepTask(
      repository: repository,
      getCurrentPosition: () =>
          Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium),
    );

    await db.close();
    return true;
  });
}

/// 앱 시작 시 1회 호출한다. 이미 등록돼 있으면 `existingWorkPolicy`가
/// 중복 등록을 막는다.
void registerFootstepBackgroundTask() {
  Workmanager().initialize(footstepCallbackDispatcher, isInDebugMode: false);
  Workmanager().registerPeriodicTask(
    footstepTaskName,
    footstepTaskName,
    frequency: const Duration(hours: 1),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.not_required),
  );
}
```

> WorkManager의 최소 주기는 15분이지만 안드로이드 시스템이 정확한 시각을 보장하지 않는다 — Doze 모드에서는 더 밀릴 수 있다. 스펙 §6-③이 이미 "무해하다"고 판단했으므로 여기서 정확도를 강제하지 않는다.

- [ ] **Step 7: 배터리 최적화 예외 요청 플로우 작성** `[실기기 필요]`

`app/lib/features/footsteps/background/battery_optimization.dart`:

```dart
import 'package:permission_handler/permission_handler.dart';

/// 최초 실행 시 1회 호출한다. 사용자가 거부해도 앱은 정상 동작해야 한다
/// (포그라운드 체크인 + Timeline 임포트가 백업 경로이므로).
Future<bool> requestIgnoreBatteryOptimization() async {
  final status = await Permission.ignoreBatteryOptimizations.status;
  if (status.isGranted) return true;

  final result = await Permission.ignoreBatteryOptimizations.request();
  return result.isGranted;
}
```

- [ ] **Step 8: `main.dart`에 배선**

`app/lib/main.dart`에 백그라운드 작업 등록을 추가한다. Firebase 초기화(다른 계획에서 이미 붙어 있음) 이후, `runApp` 이전에 호출한다.

```dart
import 'features/footsteps/background/footstep_workmanager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // ...(Firebase 초기화 등 기존 코드)
  registerFootstepBackgroundTask();
  runApp(
    ProviderScope(
      child: TravelFootstepsApp(router: createRouter(isLoggedIn: false)),
    ),
  );
}
```

배터리 최적화 예외 요청(`requestIgnoreBatteryOptimization`)은 `main.dart`가 아니라 로그인 직후 1회성 다이얼로그로 Task 8의 `FootstepsPage` 첫 진입 시 호출한다 — 앱 시작 직후 권한 팝업을 띄우면 로그인 화면 위에 겹쳐 UX가 나빠지기 때문이다.

- [ ] **Step 9: 커밋**

```bash
git add app/android/app/src/main/AndroidManifest.xml app/lib/main.dart \
  app/lib/features/footsteps/background app/test/footsteps/footstep_task_handler_test.dart
git commit -m "feat(app): WorkManager 1시간 주기 백그라운드 체크인과 배터리 최적화 예외"
```

- [ ] **Step 10: 실기기 검증** `[실기기 필요]`

제조사가 다른 실기기 최소 2종(스펙 §9 Phase 4의 "제조사별 최소 3종" 요구를 이 태스크에서 미리 1차 확인)에서:
1. 배터리 최적화 예외 다이얼로그가 뜨고, 허용/거부 모두 앱이 크래시 없이 진행되는지
2. 앱을 백그라운드로 보낸 채 1~2시간 방치 후 `allCheckins()`에 `AUTO` 소스 레코드가 쌓이는지 (Task 8의 상위 지도 화면 또는 `adb shell run-as com.travelfootsteps.app sqlite3` 로 DB 파일을 직접 확인)
3. 삼성 등 배터리 최적화가 공격적인 제조사에서 몇 시간 뒤에도 앱 프로세스 자체가 죽어 기록이 전혀 없다면 — 이는 알려진 리스크(스펙 §10)이므로 실패로 취급하지 않는다. 대신 시연 시나리오에 "포그라운드 체크인 몇 번 + Timeline 임포트로 과거 기록 채우기"를 포함하도록 팀에 공유한다.

---

### Task 4: Health Connect 걸음 수 읽기 + 국가 귀속

**Files:**
- Modify: `app/android/app/build.gradle`
- Create: `app/lib/features/footsteps/health/health_steps_service.dart`
- Create: `app/lib/features/footsteps/health/step_attribution.dart`
- Test: `app/test/footsteps/step_attribution_test.dart`

**Interfaces:**
- Consumes: Task 2의 `Checkin`, `FootstepsRepository.checkinsForCountry`는 쓰지 않고 `allCheckins()`를 날짜별로 그룹핑해 사용
- Produces:
  - `class HealthStepsService { Future<bool> requestAuthorization(); Future<int?> stepsOn(DateTime date); }` — Health Connect 래퍼. 권한 없거나 데이터 없으면 `null`.
  - `String? attributeCountryForDate(DateTime date, List<Checkin> allCheckins)` — 순수 함수. 그 날짜에 체크인이 가장 많은 국가를 반환, 체크인이 하나도 없으면 `null`.
  - `Future<void> syncTodayStepsToDatabase({required HealthStepsService health, required FootstepsRepository repository, required DateTime date})` — 위 둘을 엮어 `daily_steps`에 upsert.

> **왜 귀속 로직을 분리하는가**: `health` 패키지의 Health Connect 연동은 실제 기기의 Health Connect 앱 설치·권한 승인이 필요해 CI에서 검증할 수 없다. "그날 어느 나라에 귀속시키는가"라는 판단(가장 많이 체크인된 국가)은 순수 Dart 로직이므로 별도 함수로 빼서 여기만 확실히 단위 테스트한다.

- [ ] **Step 1: Health Connect 의존성 설정**

`app/android/app/build.gradle`의 `android { defaultConfig { ... } }`에 최소 SDK를 확인한다. `health` 패키지는 Health Connect 연동에 `minSdkVersion 26` 이상을 요구한다.

```gradle
    defaultConfig {
        applicationId "com.travelfootsteps.app"
        minSdkVersion 26
        targetSdkVersion 34
        // ... 기존 설정 유지
    }
```

`AndroidManifest.xml`에 Health Connect 권한을 추가한다.

```xml
    <uses-permission android:name="android.permission.health.READ_STEPS" />
    <queries>
        <package android:name="com.google.android.apps.healthdata" />
    </queries>
```

- [ ] **Step 2: 실패하는 귀속 로직 테스트 작성**

`app/test/footsteps/step_attribution_test.dart`:

```dart
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/health/step_attribution.dart';
import 'package:flutter_test/flutter_test.dart';

Checkin _checkin(String iso, DateTime at) => Checkin(
      id: 0,
      lat: 0,
      lng: 0,
      countryIso: iso,
      recordedAt: at,
      source: CheckinSource.auto,
      synced: false,
    );

void main() {
  test('그 날짜에 체크인이 가장 많은 국가를 반환한다', () {
    final date = DateTime.utc(2026, 12, 21);
    final checkins = [
      _checkin('VN', DateTime.utc(2026, 12, 21, 1)),
      _checkin('VN', DateTime.utc(2026, 12, 21, 10)),
      _checkin('JP', DateTime.utc(2026, 12, 21, 20)),
      _checkin('JP', DateTime.utc(2026, 12, 20, 23)), // 전날, 제외돼야 함
    ];

    expect(attributeCountryForDate(date, checkins), 'VN');
  });

  test('그 날짜에 체크인이 없으면 null을 반환한다', () {
    final date = DateTime.utc(2026, 12, 25);
    final checkins = [_checkin('VN', DateTime.utc(2026, 12, 21, 1))];

    expect(attributeCountryForDate(date, checkins), isNull);
  });

  test('동률이면 가장 이른 체크인의 국가를 반환한다', () {
    final date = DateTime.utc(2026, 12, 21);
    final checkins = [
      _checkin('JP', DateTime.utc(2026, 12, 21, 9)),
      _checkin('VN', DateTime.utc(2026, 12, 21, 15)),
    ];

    expect(attributeCountryForDate(date, checkins), 'JP');
  });
}
```

- [ ] **Step 3: 테스트 실패 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/step_attribution_test.dart
```

기대: 컴파일 실패 — `step_attribution.dart`를 찾을 수 없음.

- [ ] **Step 4: 귀속 로직 구현**

`app/lib/features/footsteps/health/step_attribution.dart`:

```dart
import '../data/checkin.dart';

/// [date](자정 기준, UTC)에 기록된 체크인 중 가장 많이 등장한 국가를 반환한다.
/// 동률이면 그날 가장 이른 체크인의 국가를 쓴다. 체크인이 없으면 null.
String? attributeCountryForDate(DateTime date, List<Checkin> allCheckins) {
  final sameDay = allCheckins.where((c) =>
      c.recordedAt.year == date.year &&
      c.recordedAt.month == date.month &&
      c.recordedAt.day == date.day).toList()
    ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

  if (sameDay.isEmpty) return null;

  final counts = <String, int>{};
  for (final c in sameDay) {
    counts.update(c.countryIso, (v) => v + 1, ifAbsent: () => 1);
  }

  final maxCount = counts.values.reduce((a, b) => a > b ? a : b);
  for (final c in sameDay) {
    if (counts[c.countryIso] == maxCount) return c.countryIso;
  }
  return null; // 도달하지 않음
}
```

- [ ] **Step 5: 테스트 통과 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/step_attribution_test.dart
```

기대: 3개 테스트 모두 PASS.

- [ ] **Step 6: Health Connect 래퍼 작성** `[실기기 필요]`

`app/lib/features/footsteps/health/health_steps_service.dart`:

```dart
import 'package:health/health.dart';

class HealthStepsService {
  HealthStepsService() : _health = Health();

  final Health _health;

  static final _types = [HealthDataType.STEPS];

  Future<bool> requestAuthorization() async {
    final granted = await _health.hasPermissions(_types) ?? false;
    if (granted) return true;
    return _health.requestAuthorization(_types);
  }

  /// [date]의 00:00~24:00(로컬 타임존) 걸음 수 합계. 권한이 없거나
  /// 데이터가 없으면 null.
  Future<int?> stepsOn(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final steps = await _health.getTotalStepsInInterval(start, end);
    return steps;
  }
}
```

- [ ] **Step 7: 귀속 결과를 DB에 반영하는 조합 함수 작성**

`step_attribution.dart` 하단에 이어서 작성한다.

```dart
import '../data/footsteps_repository.dart';
import 'health_steps_service.dart';

Future<void> syncTodayStepsToDatabase({
  required HealthStepsService health,
  required FootstepsRepository repository,
  required DateTime date,
}) async {
  final authorized = await health.requestAuthorization();
  if (!authorized) return;

  final steps = await health.stepsOn(date);
  if (steps == null) return;

  final allCheckins = await repository.allCheckins();
  final iso = attributeCountryForDate(date, allCheckins);
  if (iso == null) return; // 그날 어느 나라인지 알 수 없으면 저장하지 않는다

  await repository.upsertDailySteps(DateTime.utc(date.year, date.month, date.day), iso, steps);
}
```

> `import '../data/footsteps_repository.dart';`와 `import 'health_steps_service.dart';`는 파일 최상단으로 옮긴다 — 위에서는 설명을 위해 나눠 보였다.

- [ ] **Step 8: 전체 테스트 재실행** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/step_attribution_test.dart
```

기대: 여전히 3개 PASS (조합 함수는 Health Connect 의존이라 여기서는 유닛 테스트하지 않는다 — Step 9에서 실기기로 검증).

- [ ] **Step 9: 커밋**

```bash
git add app/android/app/build.gradle app/android/app/src/main/AndroidManifest.xml \
  app/lib/features/footsteps/health app/test/footsteps/step_attribution_test.dart
git commit -m "feat(app): Health Connect 걸음 수 읽기와 국가 귀속"
```

- [ ] **Step 10: 실기기 검증** `[실기기 필요]`

Health Connect 앱이 설치된 실기기(Android 14는 OS 내장, 그 이하는 Play Store에서 설치)에서: 권한 요청 다이얼로그 노출 확인 → 걸음 수가 있는 날짜에 대해 `syncTodayStepsToDatabase` 호출 → `daily_steps` 테이블에 값이 들어오는지 확인. Health Connect에 표본 데이터가 없으면 Google Fit이나 삼성 헬스 등 다른 걸음 수 소스 앱을 함께 설치해 Health Connect로 동기화되게 해 둔다.

---

### Task 5: Google Maps Timeline 임포트 (보조 수집 경로)

**Files:**
- Create: `app/lib/features/footsteps/import/timeline_import_parser.dart`
- Create: `app/lib/features/footsteps/import/timeline_import_page.dart`
- Test: `app/test/footsteps/timeline_import_parser_test.dart`
- Test fixture: `app/test/fixtures/timeline_export_sample.json`

**Interfaces:**
- Consumes: Task 2의 `FootstepsRepository.recordCheckinAt`, `CheckinSource.import`
- Produces: `List<TimelinePoint> parseTimelineExport(String jsonContent)` — `TimelinePoint { final double lat; final double lng; final DateTime timestamp; }`. 잘못된/알 수 없는 형식의 항목은 건너뛰고 파싱 가능한 것만 반환한다(전체 실패로 처리하지 않는다).

> **Google Timeline 내보내기 형식**: Google의 "내 활동 데이터 다운로드"(Takeout)로 받는 Timeline JSON은 버전에 따라 스키마가 다르다. 이 계획은 2024년 이후 널리 쓰이는 `semanticSegments`/`timelinePath` 형식(각 세그먼트에 `startTime`과 `point`("위도,경도" 문자열 또는 `latE7`/`lngE7` 정수) 필드가 있는 형태)을 1차로 지원하고, 알 수 없는 필드는 조용히 건너뛴다. **실제 내보내기 파일로 재검증이 필요하다** — 파서를 구현하는 사람은 자신의 Google 계정에서 Timeline을 내보내 실제 필드명을 확인하고, 아래 fixture와 파서를 그 결과에 맞게 조정한다.

- [ ] **Step 1: 샘플 fixture 작성**

`app/test/fixtures/timeline_export_sample.json`:

```json
{
  "semanticSegments": [
    {
      "startTime": "2026-12-20T09:15:00.000+09:00",
      "endTime": "2026-12-20T09:20:00.000+09:00",
      "visit": {
        "topCandidate": {
          "placeLocation": { "latLng": "35.681236, 139.767125" }
        }
      }
    },
    {
      "startTime": "2026-12-20T14:00:00.000+09:00",
      "endTime": "2026-12-20T14:05:00.000+09:00",
      "activity": {
        "start": { "latLng": "35.658034, 139.701636" },
        "end": { "latLng": "35.6586, 139.7454" }
      }
    },
    {
      "startTime": "not-a-valid-timestamp",
      "visit": { "topCandidate": { "placeLocation": { "latLng": "0,0" } } }
    }
  ]
}
```

세 번째 항목은 잘못된 타임스탬프를 가진 "깨진" 항목으로, 파서가 이를 건너뛰고 나머지 2개(방문 1개 + 이동 시작점 1개, 총 2개 좌표)만 반환하는지 검증하는 데 쓴다.

- [ ] **Step 2: 실패하는 파서 테스트 작성**

`app/test/footsteps/timeline_import_parser_test.dart`:

```dart
import 'dart:io';

import 'package:app/features/footsteps/import/timeline_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('visit과 activity 세그먼트에서 좌표를 추출한다', () {
    final json = File('test/fixtures/timeline_export_sample.json').readAsStringSync();

    final points = parseTimelineExport(json);

    expect(points, hasLength(2));
    expect(points[0].lat, closeTo(35.681236, 0.0001));
    expect(points[0].lng, closeTo(139.767125, 0.0001));
    expect(points[1].lat, closeTo(35.658034, 0.0001));
  });

  test('타임스탬프가 잘못된 세그먼트는 건너뛴다', () {
    final json = File('test/fixtures/timeline_export_sample.json').readAsStringSync();

    final points = parseTimelineExport(json);

    expect(points.any((p) => p.lat == 0 && p.lng == 0), isFalse);
  });

  test('완전히 형식이 다른 JSON을 줘도 예외 없이 빈 리스트를 반환한다', () {
    expect(parseTimelineExport('{"unrelated": true}'), isEmpty);
  });

  test('JSON 자체가 깨졌으면 빈 리스트를 반환한다', () {
    expect(parseTimelineExport('not json at all'), isEmpty);
  });
}
```

- [ ] **Step 3: 테스트 실패 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/timeline_import_parser_test.dart
```

기대: 컴파일 실패 — `timeline_import_parser.dart`를 찾을 수 없음.

- [ ] **Step 4: 파서 구현**

`app/lib/features/footsteps/import/timeline_import_parser.dart`:

```dart
import 'dart:convert';

class TimelinePoint {
  const TimelinePoint({required this.lat, required this.lng, required this.timestamp});

  final double lat;
  final double lng;
  final DateTime timestamp;
}

/// Google Maps Timeline 내보내기(Takeout) JSON을 파싱한다.
/// 알 수 없는 필드나 깨진 항목은 건너뛰고, 파싱 가능한 좌표만 시간순으로 반환한다.
List<TimelinePoint> parseTimelineExport(String jsonContent) {
  final Map<String, dynamic> root;
  try {
    root = jsonDecode(jsonContent) as Map<String, dynamic>;
  } catch (_) {
    return [];
  }

  final segments = root['semanticSegments'];
  if (segments is! List) return [];

  final points = <TimelinePoint>[];
  for (final segment in segments) {
    if (segment is! Map<String, dynamic>) continue;
    final point = _extractPoint(segment);
    if (point != null) points.add(point);
  }

  points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return points;
}

TimelinePoint? _extractPoint(Map<String, dynamic> segment) {
  final startTimeRaw = segment['startTime'];
  if (startTimeRaw is! String) return null;

  final timestamp = DateTime.tryParse(startTimeRaw);
  if (timestamp == null) return null;

  final latLng = _findLatLng(segment);
  if (latLng == null) return null;

  return TimelinePoint(lat: latLng.$1, lng: latLng.$2, timestamp: timestamp.toUtc());
}

/// visit(장소 방문)과 activity(이동) 세그먼트 둘 다에서 "latLng" 형태의
/// "위도, 경도" 문자열을 찾는다. 어느 형태에도 없으면 null.
(double, double)? _findLatLng(Map<String, dynamic> segment) {
  final visit = segment['visit'];
  if (visit is Map<String, dynamic>) {
    final raw = visit['topCandidate']?['placeLocation']?['latLng'];
    final parsed = _parseLatLngString(raw);
    if (parsed != null) return parsed;
  }

  final activity = segment['activity'];
  if (activity is Map<String, dynamic>) {
    final raw = activity['start']?['latLng'];
    final parsed = _parseLatLngString(raw);
    if (parsed != null) return parsed;
  }

  return null;
}

(double, double)? _parseLatLngString(dynamic raw) {
  if (raw is! String) return null;
  final parts = raw.split(',');
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0].trim());
  final lng = double.tryParse(parts[1].trim());
  if (lat == null || lng == null) return null;
  return (lat, lng);
}
```

- [ ] **Step 5: 테스트 통과 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/timeline_import_parser_test.dart
```

기대: 4개 테스트 모두 PASS.

- [ ] **Step 6: file_picker UI 작성** `[실기기 필요]`

`app/lib/features/footsteps/import/timeline_import_page.dart`:

```dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/checkin.dart';
import '../providers/footsteps_providers.dart';
import 'timeline_import_parser.dart';

class TimelineImportPage extends ConsumerStatefulWidget {
  const TimelineImportPage({super.key});

  @override
  ConsumerState<TimelineImportPage> createState() => _TimelineImportPageState();
}

class _TimelineImportPageState extends ConsumerState<TimelineImportPage> {
  bool _importing = false;
  String? _resultMessage;

  Future<void> _pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    final path = result?.files.single.path;
    if (path == null) return;

    setState(() => _importing = true);

    final content = await File(path).readAsString();
    final points = parseTimelineExport(content);

    final repository = ref.read(footstepsRepositoryProvider);
    for (final point in points) {
      await repository.recordCheckinAt(point.lat, point.lng, point.timestamp, CheckinSource.import);
    }

    setState(() {
      _importing = false;
      _resultMessage = '${points.length}개 지점을 가져왔습니다.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timeline 가져오기')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Google 계정 설정 > 내 활동 데이터 다운로드(Takeout)에서 '
              'Timeline(위치 기록)을 JSON으로 내보낸 뒤 그 파일을 선택하세요. '
              '앱 설치 이전의 과거 기록을 채우는 용도입니다.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _importing ? null : _pickAndImport,
              child: Text(_importing ? '가져오는 중...' : 'JSON 파일 선택'),
            ),
            if (_resultMessage != null) ...[
              const SizedBox(height: 16),
              Text(_resultMessage!),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: 커밋**

```bash
git add app/lib/features/footsteps/import app/test/footsteps/timeline_import_parser_test.dart \
  app/test/fixtures/timeline_export_sample.json
git commit -m "feat(app): Google Timeline 내보내기 JSON 임포트"
```

- [ ] **Step 8: 실기기 검증 — 실제 내보내기 파일로 재확인** `[실기기 필요]`

담당자 본인의 Google 계정에서 Timeline을 실제로 내보내(수 분~수 시간 소요될 수 있음, 미리 신청) 받은 JSON으로 임포트를 실행한다. Step 1의 fixture와 필드명이 다르면(예: 구버전 `timelineObjects`/`placeVisit` 구조), `_extractPoint`와 `_findLatLng`에 해당 구버전 분기를 추가하고 fixture에도 그 형태의 샘플을 추가해 회귀 테스트로 남긴다.

---

### Task 6: 서버 동기화 (checkin, daily_steps 배치 push)

**Files:**
- Create: `app/lib/features/footsteps/data/footsteps_api.dart`
- Create: `app/lib/features/footsteps/data/footsteps_sync_service.dart`
- Test: `app/test/footsteps/footsteps_sync_service_test.dart`

**Interfaces:**
- Consumes: Phase 0 Task 9의 `apiClientProvider`(`Provider<Dio>`), Task 1의 `unsyncedCheckins()`/`markCheckinSynced()`/`unsyncedDailySteps()`/`markDailyStepsSynced()`(`FootstepsRepository` 경유)
- Produces:
  - `abstract class FootstepsApi { Future<Map<int,String>> pushCheckins(List<Checkin> items); Future<Map<int,String>> pushDailySteps(List<DailyStep> items); }` — 로컬 id → 서버 id 매핑을 반환한다.
  - `class DioFootstepsApi implements FootstepsApi` — dio로 `POST /api/checkins`, `POST /api/daily-steps` 호출.
  - `Future<void> syncFootsteps({required FootstepsRepository repository, required FootstepsApi api})` — 미동기화 로우를 모아 배치 전송 후 각각 동기화 표시.

> **가정한 서버 계약 (미확정 — R1과 조율 필요)**: 이 계획은 앱 쪽만 다루므로 서버에 아래 두 엔드포인트가 있다고 가정하고 클라이언트를 작성한다. 실제 서버 구현은 Plan A(R1) 또는 이 기능 소유자가 별도로 추가해야 하며, 요청/응답 필드명이 확정되면 `DioFootstepsApi`만 수정하면 되도록 인터페이스(`FootstepsApi`) 뒤에 감춰 뒀다.
>
> ```
> POST /api/checkins        Body: [{lat, lng, countryIso, recordedAt, source}]
>                            Resp: [{localId, serverId}]   (요청 배열과 같은 순서)
> POST /api/daily-steps      Body: [{date, countryIso, stepCount}]
>                            Resp: [{localId, serverId}]
> ```
> 로컬 id를 요청에 실어 보내고 응답이 같은 순서로 온다고 가정한 것은 서버가 아직 없어 실제로 검증되지 않았다 — Task 7~8 진행 전에 R1과 계약을 확정한다.

- [ ] **Step 1: 실패하는 sync 서비스 테스트 작성 (가짜 API로 대체)**

`app/test/footsteps/footsteps_sync_service_test.dart`:

```dart
import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/daily_step.dart';
import 'package:app/features/footsteps/data/footsteps_api.dart';
import 'package:app/features/footsteps/data/footsteps_repository.dart';
import 'package:app/features/footsteps/data/footsteps_sync_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedCountryResolver {
  Future<String> resolveIso2(double lat, double lng) async => 'JP';
}

class _FakeFootstepsApi implements FootstepsApi {
  int nextServerId = 1;
  List<Checkin> pushedCheckins = [];
  List<DailyStep> pushedDailySteps = [];

  @override
  Future<Map<int, String>> pushCheckins(List<Checkin> items) async {
    pushedCheckins = items;
    return {for (final c in items) c.id: 'server-checkin-${nextServerId++}'};
  }

  @override
  Future<Map<int, String>> pushDailySteps(List<DailyStep> items) async {
    pushedDailySteps = items;
    return {for (final d in items) d.id: 'server-daily-${nextServerId++}'};
  }
}

void main() {
  late AppDatabase db;
  late FootstepsRepository repo;
  late _FakeFootstepsApi api;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FootstepsRepository(db: db, countryResolver: _CountryResolverAdapter());
    api = _FakeFootstepsApi();
  });

  tearDown(() => db.close());

  test('미동기화 체크인과 걸음수를 배치로 보내고 동기화 표시한다', () async {
    await repo.recordCheckinAt(35.6, 139.7, DateTime.utc(2026, 12, 20, 9), CheckinSource.auto);
    await repo.upsertDailySteps(DateTime.utc(2026, 12, 20), 'JP', 5000);

    await syncFootsteps(repository: repo, api: api);

    expect(api.pushedCheckins, hasLength(1));
    expect(api.pushedDailySteps, hasLength(1));
    expect(await repo.unsyncedCheckins(), isEmpty);
    expect(await db.unsyncedDailySteps(), isEmpty);
  });

  test('보낼 것이 없으면 API를 호출하지 않는다', () async {
    await syncFootsteps(repository: repo, api: api);

    expect(api.pushedCheckins, isEmpty);
    expect(api.pushedDailySteps, isEmpty);
  });
}

class _CountryResolverAdapter implements _FixedCountryResolver {
  @override
  Future<String> resolveIso2(double lat, double lng) async => 'JP';
}
```

> `_CountryResolverAdapter`가 어색하게 보이면 실제 구현 시 `import '.../data/country_resolver.dart';`의 `CountryResolver`를 직접 구현하도록 정리한다 — 위 테스트의 핵심은 sync 로직이지 국가 판정이 아니므로, `FootstepsRepository`가 요구하는 실제 `CountryResolver` 인터페이스를 구현하는 간단한 fake 하나로 교체해서 작성한다.

- [ ] **Step 2: 테스트 실패 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/footsteps_sync_service_test.dart
```

기대: 컴파일 실패 — `footsteps_api.dart`, `footsteps_sync_service.dart`를 찾을 수 없음.

- [ ] **Step 3: `FootstepsApi` 인터페이스와 dio 구현체 작성**

`app/lib/features/footsteps/data/footsteps_api.dart`:

```dart
import 'package:dio/dio.dart';

import 'checkin.dart';
import 'daily_step.dart';

abstract class FootstepsApi {
  Future<Map<int, String>> pushCheckins(List<Checkin> items);
  Future<Map<int, String>> pushDailySteps(List<DailyStep> items);
}

class DioFootstepsApi implements FootstepsApi {
  DioFootstepsApi(this._dio);

  final Dio _dio;

  @override
  Future<Map<int, String>> pushCheckins(List<Checkin> items) async {
    if (items.isEmpty) return {};

    final response = await _dio.post<List<dynamic>>('/api/checkins', data: [
      for (final c in items)
        {
          'localId': c.id,
          'lat': c.lat,
          'lng': c.lng,
          'countryIso': c.countryIso,
          'recordedAt': c.recordedAt.toIso8601String(),
          'source': c.source.name.toUpperCase(),
        },
    ]);

    return {
      for (final row in response.data!)
        (row as Map<String, dynamic>)['localId'] as int: row['serverId'] as String,
    };
  }

  @override
  Future<Map<int, String>> pushDailySteps(List<DailyStep> items) async {
    if (items.isEmpty) return {};

    final response = await _dio.post<List<dynamic>>('/api/daily-steps', data: [
      for (final d in items)
        {
          'localId': d.id,
          'date': d.date.toIso8601String(),
          'countryIso': d.countryIso,
          'stepCount': d.stepCount,
        },
    ]);

    return {
      for (final row in response.data!)
        (row as Map<String, dynamic>)['localId'] as int: row['serverId'] as String,
    };
  }
}
```

- [ ] **Step 4: sync 서비스 구현**

`app/lib/features/footsteps/data/footsteps_sync_service.dart`:

```dart
import 'footsteps_api.dart';
import 'footsteps_repository.dart';

Future<void> syncFootsteps({
  required FootstepsRepository repository,
  required FootstepsApi api,
}) async {
  final unsyncedCheckins = await repository.unsyncedCheckins();
  if (unsyncedCheckins.isNotEmpty) {
    final serverIds = await api.pushCheckins(unsyncedCheckins);
    for (final entry in serverIds.entries) {
      await repository.markCheckinSynced(entry.key, entry.value);
    }
  }

  final unsyncedDailySteps = await repository.unsyncedDailySteps();
  if (unsyncedDailySteps.isNotEmpty) {
    final serverIds = await api.pushDailySteps(unsyncedDailySteps);
    for (final entry in serverIds.entries) {
      await repository.markDailyStepsSynced(entry.key, entry.value);
    }
  }
}
```

- [ ] **Step 5: 테스트 통과 확인 (테스트 파일의 fake `CountryResolver` 배선 정리 포함)** `[단위 테스트로 검증 가능]`

Step 1의 테스트에서 `_FixedCountryResolver`/`_CountryResolverAdapter`를 실제 `CountryResolver` 인터페이스를 구현하는 단일 클래스로 정리한 뒤 실행한다.

```bash
cd app && flutter test test/footsteps/footsteps_sync_service_test.dart
```

기대: 2개 테스트 모두 PASS.

- [ ] **Step 6: Riverpod provider와 주기 동기화 배선**

`app/lib/features/footsteps/providers/footsteps_providers.dart`에 추가한다.

```dart
import '../data/footsteps_api.dart';
import '../data/footsteps_sync_service.dart';
import '../../../core/network/api_client.dart';

final footstepsApiProvider = Provider<FootstepsApi>((ref) {
  return DioFootstepsApi(ref.watch(apiClientProvider));
});

Future<void> runFootstepsSync(WidgetRef ref) {
  return syncFootsteps(
    repository: ref.read(footstepsRepositoryProvider),
    api: ref.read(footstepsApiProvider),
  );
}
```

`FootstepsPage`(Task 8)가 화면 진입 시(`initState`)와 당겨서 새로고침(pull-to-refresh) 시 `runFootstepsSync`를 호출한다. 스펙에 별도 동기화 주기 요구가 없으므로 별도 WorkManager 작업을 새로 만들지 않고 앱 사용 시점에 맞춰 동기화한다.

- [ ] **Step 7: 커밋**

```bash
git add app/lib/features/footsteps/data/footsteps_api.dart \
  app/lib/features/footsteps/data/footsteps_sync_service.dart \
  app/lib/features/footsteps/providers/footsteps_providers.dart \
  app/test/footsteps/footsteps_sync_service_test.dart
git commit -m "feat(app): 체크인·걸음수 서버 동기화"
```

---

### Task 7: 상위 지도 — 세계지도 choropleth + 국가별 누적 걸음 카드

**Files:**
- Create: `app/assets/geo/world_countries.geojson`
- Create: `app/lib/features/footsteps/map/base_google_map.dart`
- Create: `app/lib/features/footsteps/map/world_geojson_parser.dart`
- Create: `app/lib/features/footsteps/map/world_map_page.dart`
- Test: `app/test/footsteps/world_geojson_parser_test.dart`

**Interfaces:**
- Consumes: Task 2의 `footstepsRepositoryProvider`(`cumulativeStepsByCountry()`)
- Produces:
  - `class BaseGoogleMap extends StatelessWidget { const BaseGoogleMap({required this.initialCamera, this.polygons = const {}, this.markers = const {}, this.polylines = const {}, this.onMapCreated}); }` — Plan F가 재사용하는 재사용 가능한 지도 셸.
  - `List<CountryPolygon> parseWorldGeoJson(String geoJsonContent)` — `CountryPolygon { final String isoAlpha2; final List<List<LatLng>> rings; }`
  - `WorldMapPage` 위젯 — 방문국 채색 + 하단 국가 카드 목록(탭하면 `onCountryTap(String iso)` 콜백).

> **GeoJSON 데이터 출처**: `app/assets/geo/world_countries.geojson`은 이 계획에 포함하지 않은 외부 데이터 파일이다. 공개 도메인 국가 경계 데이터(예: Natural Earth 110m 또는 `datasets/geo-countries` 저장소의 `countries.geojson`, ISO-3166 alpha-2 속성을 포함하는 것)를 받아 이 경로에 둔다. 파일 용량이 크면(수 MB) 저해상도(110m 축척)를 쓴다 — 이 앱은 국가 단위 채색이 목적이라 정밀한 해안선이 필요 없다.

- [ ] **Step 1: 재사용 가능한 지도 셸 작성**

`app/lib/features/footsteps/map/base_google_map.dart`:

```dart
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';

/// Plan F(주변 여행 정보)가 Places 마커를 얹어 재사용할 수 있도록
/// 지도 초기화·오버레이 렌더링만 책임지는 셸.
class BaseGoogleMap extends StatelessWidget {
  const BaseGoogleMap({
    super.key,
    required this.initialCamera,
    this.polygons = const {},
    this.markers = const {},
    this.polylines = const {},
    this.onMapCreated,
    this.onTap,
  });

  final CameraPosition initialCamera;
  final Set<Polygon> polygons;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final void Function(GoogleMapController controller)? onMapCreated;
  final void Function(LatLng position)? onTap;

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: initialCamera,
      polygons: polygons,
      markers: markers,
      polylines: polylines,
      onMapCreated: onMapCreated,
      onTap: onTap,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }
}
```

- [ ] **Step 2: 실패하는 GeoJSON 파서 테스트 작성**

`app/test/footsteps/world_geojson_parser_test.dart`:

```dart
import 'package:app/features/footsteps/map/world_geojson_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleGeoJson = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": { "ISO_A2": "JP" },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[139.0, 35.0], [140.0, 35.0], [140.0, 36.0], [139.0, 36.0], [139.0, 35.0]]]
      }
    },
    {
      "type": "Feature",
      "properties": { "ISO_A2": "-99" },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 0.0]]]
      }
    },
    {
      "type": "Feature",
      "properties": { "ISO_A2": "VN" },
      "geometry": {
        "type": "MultiPolygon",
        "coordinates": [
          [[[105.0, 21.0], [106.0, 21.0], [106.0, 22.0], [105.0, 21.0]]],
          [[[107.0, 20.0], [108.0, 20.0], [108.0, 21.0], [107.0, 20.0]]]
        ]
      }
    }
  ]
}
''';

void main() {
  test('Polygon 지오메트리에서 국가 코드와 링 좌표를 추출한다', () {
    final countries = parseWorldGeoJson(_sampleGeoJson);

    final japan = countries.firstWhere((c) => c.isoAlpha2 == 'JP');
    expect(japan.rings, hasLength(1));
    expect(japan.rings.first, hasLength(5));
  });

  test('ISO_A2가 -99(미분류, 예: 소말릴란드 등 미승인 지역)인 항목은 건너뛴다', () {
    final countries = parseWorldGeoJson(_sampleGeoJson);

    expect(countries.any((c) => c.isoAlpha2 == '-99'), isFalse);
  });

  test('MultiPolygon은 여러 링으로 펼쳐진다', () {
    final countries = parseWorldGeoJson(_sampleGeoJson);

    final vietnam = countries.firstWhere((c) => c.isoAlpha2 == 'VN');
    expect(vietnam.rings, hasLength(2));
  });
}
```

- [ ] **Step 3: 테스트 실패 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/world_geojson_parser_test.dart
```

기대: 컴파일 실패 — `world_geojson_parser.dart`를 찾을 수 없음.

- [ ] **Step 4: 파서 구현**

`app/lib/features/footsteps/map/world_geojson_parser.dart`:

```dart
import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';

class CountryPolygon {
  const CountryPolygon({required this.isoAlpha2, required this.rings});

  final String isoAlpha2;
  final List<List<LatLng>> rings;
}

/// Natural Earth 계열 GeoJSON(FeatureCollection, properties.ISO_A2 보유)을 파싱한다.
List<CountryPolygon> parseWorldGeoJson(String geoJsonContent) {
  final root = jsonDecode(geoJsonContent) as Map<String, dynamic>;
  final features = root['features'] as List<dynamic>? ?? [];

  final result = <CountryPolygon>[];
  for (final feature in features) {
    final map = feature as Map<String, dynamic>;
    final iso = map['properties']?['ISO_A2'] as String?;
    if (iso == null || iso.length != 2) continue; // '-99' 등 미분류 제외

    final geometry = map['geometry'] as Map<String, dynamic>?;
    if (geometry == null) continue;

    final rings = _extractRings(geometry);
    if (rings.isEmpty) continue;

    result.add(CountryPolygon(isoAlpha2: iso, rings: rings));
  }
  return result;
}

List<List<LatLng>> _extractRings(Map<String, dynamic> geometry) {
  final type = geometry['type'] as String?;
  final coordinates = geometry['coordinates'];

  if (type == 'Polygon') {
    return [_ringFromCoords(coordinates[0] as List<dynamic>)];
  }
  if (type == 'MultiPolygon') {
    return [
      for (final polygon in coordinates as List<dynamic>)
        _ringFromCoords((polygon as List<dynamic>)[0] as List<dynamic>),
    ];
  }
  return [];
}

List<LatLng> _ringFromCoords(List<dynamic> coords) {
  return [
    for (final point in coords)
      LatLng((point as List<dynamic>)[1] as double, point[0] as double),
  ];
}
```

- [ ] **Step 5: 테스트 통과 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test test/footsteps/world_geojson_parser_test.dart
```

기대: 3개 테스트 모두 PASS.

- [ ] **Step 6: GeoJSON 에셋 배치** `[실기기 필요]`

담당자가 위 "GeoJSON 데이터 출처"에서 설명한 공개 데이터를 내려받아 `app/assets/geo/world_countries.geojson`에 저장한다. 각 feature의 국가 코드 속성 키가 `ISO_A2`가 아니면(`ISO_A2_EH`, `iso_a2`, `ADM0_A3` 등 소스마다 다름) `world_geojson_parser.dart`의 `map['properties']?['ISO_A2']` 부분을 실제 키로 바꾸고, Step 2의 테스트 fixture도 그 키 이름으로 맞춰 갱신한다.

- [ ] **Step 7: 상위 지도 화면 작성** `[실기기 필요]`

`app/lib/features/footsteps/map/world_map_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../providers/footsteps_providers.dart';
import 'base_google_map.dart';
import 'world_geojson_parser.dart';

final _worldGeoJsonProvider = FutureProvider<List<CountryPolygon>>((ref) async {
  final content = await rootBundle.loadString('assets/geo/world_countries.geojson');
  return parseWorldGeoJson(content);
});

final _cumulativeStepsProvider = FutureProvider<Map<String, int>>((ref) {
  return ref.watch(footstepsRepositoryProvider).cumulativeStepsByCountry();
});

class WorldMapPage extends ConsumerWidget {
  const WorldMapPage({super.key, required this.onCountryTap});

  final void Function(String isoAlpha2) onCountryTap;

  static const _visitedFill = Color(0x992563EB); // 반투명 파랑
  static const _visitedStroke = Color(0xFF2563EB);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final polygonsAsync = ref.watch(_worldGeoJsonProvider);
    final stepsAsync = ref.watch(_cumulativeStepsProvider);

    return polygonsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('지도를 불러오지 못했습니다\n$e')),
      data: (allCountries) {
        final visitedIsos = stepsAsync.valueOrNull?.keys.toSet() ?? {};
        final polygons = <Polygon>{
          for (final country in allCountries)
            if (visitedIsos.contains(country.isoAlpha2))
              for (var i = 0; i < country.rings.length; i++)
                Polygon(
                  polygonId: PolygonId('${country.isoAlpha2}_$i'),
                  points: country.rings[i],
                  fillColor: _visitedFill,
                  strokeColor: _visitedStroke,
                  strokeWidth: 1,
                  consumeTapEvents: true,
                  onTap: () => onCountryTap(country.isoAlpha2),
                ),
        };

        return Column(
          children: [
            Expanded(
              child: BaseGoogleMap(
                initialCamera: const CameraPosition(target: LatLng(20, 0), zoom: 2),
                polygons: polygons,
              ),
            ),
            SizedBox(
              height: 120,
              child: stepsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('걸음 수를 불러오지 못했습니다\n$e'),
                data: (totals) => _CountryStepsList(totals: totals, onTap: onCountryTap),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CountryStepsList extends StatelessWidget {
  const _CountryStepsList({required this.totals, required this.onTap});

  final Map<String, int> totals;
  final void Function(String isoAlpha2) onTap;

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) {
      return const Center(child: Text('아직 기록된 발걸음이 없습니다'));
    }
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final entry in entries)
          Card(
            child: InkWell(
              onTap: () => onTap(entry.key),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${entry.value}보'),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 8: 커밋**

```bash
git add app/assets/geo app/lib/features/footsteps/map/base_google_map.dart \
  app/lib/features/footsteps/map/world_geojson_parser.dart \
  app/lib/features/footsteps/map/world_map_page.dart \
  app/test/footsteps/world_geojson_parser_test.dart
git commit -m "feat(app): 상위 세계지도 choropleth와 국가별 걸음 카드"
```

- [ ] **Step 9: 실기기 검증** `[실기기 필요]`

실기기(또는 Google Play 서비스가 있는 에뮬레이터)에서 Maps API 키가 올바르게 로드되는지(회색 격자 지도만 보이면 키 문제), 방문국이 채색되는지, 카드를 탭하면 `onCountryTap`이 호출되는지 확인한다.

---

### Task 8: 하위 지도 — 국가별 점선 경로 + `FootstepsPage` 통합

**Files:**
- Modify: `app/lib/features/footsteps/footsteps_page.dart`
- Create: `app/lib/features/footsteps/map/country_detail_map_page.dart`

**Interfaces:**
- Consumes: Task 2의 `footstepsRepositoryProvider.checkinsForCountry`, Task 3의 `requestIgnoreBatteryOptimization`, Task 6의 `runFootstepsSync`, Task 7의 `WorldMapPage`, Task 5의 `TimelineImportPage`
- Produces: `FootstepsPage` — Phase 0이 만든 라우팅 셸(`app/lib/features/footsteps/footsteps_page.dart`)의 최종 내용. go_router에 새 라우트를 추가하지 않고, 내부 상태(`String? _selectedCountryIso`)로 상위/하위 화면을 전환한다.

- [ ] **Step 1: 하위 지도(국가 상세) 화면 작성** `[실기기 필요]`

`app/lib/features/footsteps/map/country_detail_map_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/checkin.dart';
import '../providers/footsteps_providers.dart';
import 'base_google_map.dart';

final _checkinsForCountryProvider =
    FutureProvider.family<List<Checkin>, String>((ref, iso) {
  return ref.watch(footstepsRepositoryProvider).checkinsForCountry(iso);
});

class CountryDetailMapPage extends ConsumerStatefulWidget {
  const CountryDetailMapPage({super.key, required this.isoAlpha2, required this.onBack});

  final String isoAlpha2;
  final VoidCallback onBack;

  @override
  ConsumerState<CountryDetailMapPage> createState() => _CountryDetailMapPageState();
}

class _CountryDetailMapPageState extends ConsumerState<CountryDetailMapPage> {
  DateTime? _selectedDate;

  @override
  Widget build(BuildContext context) {
    final checkinsAsync = ref.watch(_checkinsForCountryProvider(widget.isoAlpha2));

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.isoAlpha2} 이동 경로'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
      ),
      body: checkinsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('경로를 불러오지 못했습니다\n$e')),
        data: (checkins) {
          if (checkins.isEmpty) {
            return const Center(child: Text('이 나라의 체크인 기록이 없습니다'));
          }

          final byDate = <DateTime, List<Checkin>>{};
          for (final c in checkins) {
            final day = DateTime.utc(c.recordedAt.year, c.recordedAt.month, c.recordedAt.day);
            byDate.putIfAbsent(day, () => []).add(c);
          }
          final dates = byDate.keys.toList()..sort();
          final selected = _selectedDate ?? dates.last;
          final dayCheckins = byDate[selected] ?? [];

          final points = [for (final c in dayCheckins) LatLng(c.lat, c.lng)];

          return Column(
            children: [
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final date in dates)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text('${date.month}/${date.day}'),
                          selected: date == selected,
                          onSelected: (_) => setState(() => _selectedDate = date),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: BaseGoogleMap(
                  initialCamera: CameraPosition(target: points.first, zoom: 11),
                  markers: {
                    for (var i = 0; i < dayCheckins.length; i++)
                      Marker(
                        markerId: MarkerId('checkin_$i'),
                        position: points[i],
                        infoWindow: InfoWindow(
                          title: '${dayCheckins[i].recordedAt.toLocal()}',
                          snippet: dayCheckins[i].source.name,
                        ),
                      ),
                  },
                  polylines: {
                    Polyline(
                      polylineId: const PolylineId('day_route'),
                      points: points,
                      color: const Color(0xFF2563EB),
                      width: 3,
                      patterns: [PatternItem.dot, PatternItem.gap(8)], // 시간순 점선 연결
                    ),
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: `FootstepsPage` 최종 구현**

`app/lib/features/footsteps/footsteps_page.dart` 전체를 아래로 교체한다. Task 2 Step 12에서 붙인 임시 "여기 저장" 버튼은 여기서 정식 위치로 옮겨진다.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'background/battery_optimization.dart';
import 'import/timeline_import_page.dart';
import 'map/country_detail_map_page.dart';
import 'map/world_map_page.dart';
import 'providers/footsteps_providers.dart';

class FootstepsPage extends ConsumerStatefulWidget {
  const FootstepsPage({super.key});

  @override
  ConsumerState<FootstepsPage> createState() => _FootstepsPageState();
}

class _FootstepsPageState extends ConsumerState<FootstepsPage> {
  String? _selectedCountryIso;
  bool _batteryPromptShown = false;

  @override
  void initState() {
    super.initState();
    // 화면 진입 시 최신 상태로 동기화한다. 실패해도 조용히 무시한다 —
    // 오프라인이어도 로컬 기록·조회는 계속 동작해야 한다.
    Future.microtask(() async {
      try {
        await runFootstepsSync(ref);
      } catch (_) {}
      if (!_batteryPromptShown && mounted) {
        _batteryPromptShown = true;
        await requestIgnoreBatteryOptimization();
      }
    });
  }

  Future<void> _recordManualCheckin() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(footstepsRepositoryProvider).recordManualCheckin();
      messenger.showSnackBar(const SnackBar(content: Text('현재 위치를 저장했습니다')));
      setState(() {}); // 상위 지도의 누적 걸음 카드 갱신을 위해 다시 그린다
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedCountryIso != null) {
      return CountryDetailMapPage(
        isoAlpha2: _selectedCountryIso!,
        onBack: () => setState(() => _selectedCountryIso = null),
      );
    }

    return Scaffold(
      body: WorldMapPage(
        onCountryTap: (iso) => setState(() => _selectedCountryIso = iso),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'timeline_import',
            tooltip: 'Timeline 가져오기',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TimelineImportPage()),
            ),
            child: const Icon(Icons.file_upload_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'manual_checkin',
            onPressed: _recordManualCheckin,
            icon: const Icon(Icons.my_location),
            label: const Text('여기 저장'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: `flutter analyze` 통과 확인** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter analyze
```

기대: 무경고. Task 2 Step 12에서 붙인 임시 버튼 코드가 남아 있다면 지운다.

- [ ] **Step 4: 전체 테스트 재실행** `[단위 테스트로 검증 가능]`

```bash
cd app && flutter test
```

기대: Phase 0이 만든 테스트(`router_test.dart`, `auth_state_test.dart`, `api_client_test.dart`)와 이 계획의 모든 테스트가 함께 PASS한다. `router_test.dart`의 "탭을 누르면 해당 화면으로 이동한다" 테스트가 `find.text('발걸음')`을 찾는데, `FootstepsPage`가 이제 지도를 렌더링하므로 `google_maps_flutter`의 플랫폼 채널이 위젯 테스트 환경에 없어 실패할 수 있다 — 실패하면 `router_test.dart`의 해당 어서션에 `google_maps_flutter_platform_interface`의 테스트용 목(mock) 등록이 필요하다는 것이므로, Phase 0 담당자(R2)와 조율해 `flutter_test`의 `setUpAll`에 `GoogleMapsFlutterPlatform.instance = _FakeGoogleMapsFlutterPlatform();` 같은 목 등록을 추가한다.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/footsteps/footsteps_page.dart app/lib/features/footsteps/map/country_detail_map_page.dart
git commit -m "feat(app): 발걸음 탭 최종 UI — 상위/하위 지도, 수동 체크인, Timeline 임포트 진입점"
```

- [ ] **Step 6: 통합 실기기 시연 리허설** `[실기기 필요]`

Phase 4(스펙 §9)의 리허설 전에 이 계획 단독으로 한 번 더 확인한다: 로그인 → 발걸음 탭 진입 → "여기 저장" 몇 번 → Timeline JSON 임포트 → 상위 지도에 방문국 채색·카드 표시 → 카드 탭 → 하위 지도에서 날짜 칩 전환하며 점선 경로 확인. 이 흐름이 전부 되면 백그라운드 자동 추적이 기기에서 죽어도 시연이 가능하다(스펙 §10 백업 경로 확인 완료).

---

## Self-Review

**1. 스펙 커버리지**
- `google_maps_flutter` 통합, `geolocator` 권한 플로우 → Task 2, 7, 8
- 상위 지도(choropleth + 누적 걸음 카드) → Task 7
- 하위 지도(국가 탭 → 날짜별 점선 경로) → Task 8
- 백그라운드 자동(WorkManager 1시간) + 배터리 최적화 예외 → Task 3
- 포그라운드 수동("여기 저장") → Task 2, 8
- Timeline 임포트(file_picker + 파싱) → Task 5
- Health Connect 일별 걸음 수 → 국가 귀속 → Task 4
- 로컬 drift 캐시(`checkins`, `daily_steps`) + 서버 동기화 → Task 1, 6
- Plan F 재사용 힌트(지도 위젯 분리) → Task 7의 `BaseGoogleMap`
- 실기기 필요/단위 테스트 가능 구분 → 각 Task의 Step마다 태그 부여
- 백업 경로(스펙 §10) → Global Constraints에 명시 + Task 8 Step 6에서 통합 리허설로 재확인

빠짐없이 커버됨을 확인했다.

**2. Placeholder 스캔**
"TBD", "나중에 구현" 류의 표현 없음. 모든 코드 스텝에 실제 구현 전문을 포함했다. 예외적으로 Task 6의 서버 계약과 Task 7의 GeoJSON 속성 키, Task 5의 Timeline 실제 스키마 3곳은 "실물 확인 전 가정"임을 명시적으로 밝혔다 — 이는 placeholder가 아니라 이 계획이 통제할 수 없는 외부 의존성(서버 미구현, 서드파티 데이터 파일, Google이 통제하는 내보내기 포맷)에 대한 정직한 리스크 기록이며, 각각 실기기 검증 스텝에서 재조정하는 절차를 뒀다.

**3. 타입 일관성**
- `CheckinSource` enum(`auto`/`manual`/`import`)이 Task 1(모델)→Task 2(repository)→Task 3(WorkManager)→Task 5(임포트)→Task 6(API 직렬화) 전체에서 동일하게 쓰였다.
- `FootstepsRepository`의 메서드 시그니처(`recordCheckinAt`, `checkinsForCountry`, `cumulativeStepsByCountry`, `unsyncedCheckins`, `markCheckinSynced`, `unsyncedDailySteps`, `markDailyStepsSynced`, `upsertDailySteps`)가 Task 2에서 정의된 그대로 Task 3~8에서 사용됐다.
- `CountryResolver.resolveIso2`가 Task 2에서 정의되고 Task 3(WorkManager 콜백), Task 5(임포트, 단 임포트는 `recordCheckinAt`을 통해 간접 사용)에서 같은 시그니처로 재사용됐다.
- `apiClientProvider`(Phase 0 Task 9 산출물)를 Task 6에서 정확히 그 이름으로 재사용했다.

---

## 다음 계획서와의 접점

- **Plan A(서버, R1)**: Task 6에서 가정한 `POST /api/checkins`, `POST /api/daily-steps` 계약이 Plan A의 현재 태스크 목록(공공데이터 파이프라인 + 비자 규칙 엔진)에 명시적으로 없다. R1과 조율해 이 두 엔드포인트를 어느 계획이 만들지 확정해야 한다 — Task 6은 계약이 바뀌어도 `FootstepsApi` 인터페이스 뒤에서 흡수되도록 설계했다.
- **Plan D(그룹 위치공유, R2)**: 5초 STOMP 실시간 위치는 이 계획의 범위 밖이다. `checkin`/`daily_steps`는 이 계획이 전담하며 Plan D는 별도의 휘발성 위치 스트림을 쓴다.
- **Plan F(주변 여행 정보, R3, W9~10)**: `BaseGoogleMap`(Task 7)을 재사용해 Places 마커를 얹을 수 있다.
