# 3단계 — 환율 알림 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 준비물 탭의 환전 항목에서 들어가는 환율 알림 화면을 만든다. 여기서 매일 등락 알림과 목표 환율을 설정한다. WorkManager가 3시간마다 서버 환율을 확인해 조건이 맞으면 기기 로컬 알림을 보낸다.

**Architecture:**
- **판단은 순수 함수가 한다.** `evaluateRateAlerts`가 "설정 + 환율 → 바뀐 설정 + 보낼 알림"을 계산한다.
- **설정 저장.** `RateAlertStore`가 `shared_preferences`의 `rateAlerts.v1` 키에 통화별 설정을 저장한다.
- **백그라운드 작업.** 공용 WorkManager 디스패처가 작업 이름(발걸음/환율)으로 핸들러를 고른다. 환율 핸들러는 다음 순서로 돈다: 설정 읽기 → 서버 조회 → 지갑 환율 캐시 갱신 → 판단 → 알림 → 설정 저장.
- **바깥 세계는 인터페이스 뒤에 둔다.** 알림 발송, 권한 요청, 작업 등록은 각각 `RateNotifier`, `NotificationPermission`, `RateAlertScheduler` 인터페이스 뒤에 두어 테스트에서 가짜로 바꾼다.

**Tech Stack:** Flutter, Riverpod 3.4.3, shared_preferences, workmanager 0.10.10, flutter_local_notifications 22.3.1(신규), permission_handler 13, intl.

**Spec:** `docs/superpowers/specs/2026-10-09-wallet-exchange-alerts-design.md` §6. 이 계획은 1·2단계(PR #17, 브랜치 `wallet`) 위에서 진행한다.

## Global Constraints

- 모든 경로는 `app/` 기준이다. 명령도 `app/`에서 실행한다.
- **정적 분석은 `dart analyze`로 한다.** 이 PC에서는 `flutter analyze`가 한글 경로 때문에 죽는다. 목표 결과는 `No issues found!`다.
- 테스트는 `flutter test`로 돌린다. 기존 269개가 계속 통과해야 한다.
- **Riverpod 3 규칙**
  - `AsyncValue.value`는 nullable이다.
  - family 프로바이더 오버라이드는 `overrideWith((ref, arg) => …)` 형태로 쓴다.
  - `StateProvider`는 `package:flutter_riverpod/legacy.dart`에 있다.
- **알림 문구**(설계 §6.4)
  - 등락: `엔화 100엔 847.46원 · 전 영업일보다 ▲3.57원(0.42%)`
  - 목표: `엔화 100엔 845.00원 (목표 850원 이하)`
  - 알림 제목은 `환율 등락 알림` / `목표 환율 도달`이다.
- **알림 채널**은 id `rate_alerts`, 이름 `환율 알림`이다. 알림을 누르면 앱이 열린다(플러그인 기본 동작이며 딥링크는 범위 밖이다).
- **WorkManager 작업**
  - 이름은 `com.travelfootsteps.rateAlert`이다. 기존 `com.travelfootsteps.footstepCheckin`과 같은 규칙이며, 설계 §6.3의 `rateAlert`에 패키지 접두어를 붙였다.
  - 3시간 주기, `NetworkType.connected`, `ExistingPeriodicWorkPolicy.keep`이다.
  - 알림이 하나라도 켜져 있으면 등록하고, 하나도 없으면 취소한다.
- **목표 환율 저장 방식.** 사용자가 본 그대로 **표시 단위(`unit`) + 그 단위당 원화(`targetKrw`)**로 저장하고, 1단위 기준 값은 `krwPerUnit = targetKrw / unit`으로 계산한다. 비교는 표시 단위 금액을 **원 단위 소수 둘째 자리(전)로 반올림한 정수**끼리 한다. 그래서 경계값(같을 때)이 실수 오차 없이 발송된다.
- 앱(Dart) 코드에는 Spring 학습 주석 규칙이 적용되지 않는다. 주석은 기존 지갑 코드처럼 한국어로 "왜"를 짧게 적는다.
- **커밋**
  - 메시지는 `feat(app): …`/`fix(app): …` 형식의 한국어로 쓴다.
  - **`Co-Authored-By` 같은 AI 표기를 절대 넣지 않는다.** push하지 않는다.
  - `local.properties`, `google-services.json`, `.env`는 커밋하지 않는다.

## File Structure

| 파일 | 책임 |
|---|---|
| `lib/features/rate_alert/domain/rate_alert_settings.dart` (신규) | `TargetDirection`, `RateTarget`, `RateAlertSettings`, JSON, `newTargetId`, `formatTargetKrw` |
| `lib/features/rate_alert/domain/rate_alert_evaluator.dart` (신규) | 순수 판단 함수 `evaluateRateAlerts`, `isTargetReached`, 알림 문구 |
| `lib/features/rate_alert/data/rate_alert_store.dart` (신규) | `rateAlerts.v1` 읽기/쓰기, 프로바이더 |
| `lib/features/rate_alert/notify/rate_notifier.dart` (신규) | `RateNotifier` 인터페이스 + `flutter_local_notifications` 구현 |
| `lib/features/rate_alert/notify/notification_permission.dart` (신규) | `NotificationPermission` 인터페이스 + `permission_handler` 구현 + 프로바이더 |
| `lib/features/rate_alert/background/rate_alert_scheduler.dart` (신규) | 작업 이름 상수, `RateAlertScheduler` 인터페이스 + WorkManager 구현 + 프로바이더 |
| `lib/features/rate_alert/background/rate_alert_task.dart` (신규) | `handleRateAlertTask`(테스트 대상) + `runRateAlertTask`(백그라운드 isolate 배선) |
| `lib/core/background/app_callback_dispatcher.dart` (신규) | 공용 디스패처, `dispatchBackgroundTask`, `initializeBackgroundWork` |
| `lib/features/footsteps/background/footstep_workmanager.dart` (수정) | 디스패처 대신 `runFootstepTask()`를 내보낸다. 등록 시 `initialize`를 하지 않는다 |
| `lib/main.dart` (수정) | `initializeBackgroundWork()`를 먼저 부른다 |
| `lib/features/wallet/widgets/sub_page_header.dart` (신규) | 지갑/환율 알림이 같이 쓰는 뒤로가기 헤더 |
| `lib/features/wallet/wallet_page.dart` (수정) | `_WalletHeader`를 `SubPageHeader`로 대체 |
| `lib/features/rate_alert/rate_alert_page.dart` (신규) | 환율 알림 화면 |
| `lib/router.dart` (수정) | `/checklist/rate-alert?iso=` 라우트 |
| `lib/features/checklist/checklist_page.dart` (수정) | 환전 섹션 끝에 `환율 알림 ›` 행 |
| `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts` (수정) | 알림 플러그인, `POST_NOTIFICATIONS`, desugaring |

---

### Task 1: 알림 설정 모델과 판단 로직

**Files:**
- Create: `lib/features/rate_alert/domain/rate_alert_settings.dart`
- Create: `lib/features/rate_alert/domain/rate_alert_evaluator.dart`
- Test: `test/rate_alert/rate_alert_settings_test.dart`
- Test: `test/rate_alert/rate_alert_evaluator_test.dart`

**Interfaces:**
- Consumes (기존):
  - `ExchangeRate`(`lib/features/wallet/data/exchange_rate.dart`): `krwRate`, `baseDate`, `previousKrwRate`, `changePercent`
  - `CurrencyInfo`(`lib/features/wallet/domain/currency_info.dart`): `nameKo`, `displayUnit(double)`, `unitLabel(int)`
  - `formatKrwRate(double)`, `currencyInfoOf(String)`
- Produces:
  - `enum TargetDirection { below, above }`: `code`(`'BELOW'`/`'ABOVE'`), `labelKo`(`'이하'`/`'이상'`), `static TargetDirection fromCode(String)`
  - `class RateTarget`
    - 필드: `id`(int), `unit`(int), `targetKrw`(double), `direction`, `active`(bool), `createdAt`(DateTime), `firedAt`(DateTime?)
    - getter: `krwPerUnit`
    - 메서드: `copyWith({bool? active, DateTime? firedAt, bool clearFiredAt = false})`, `toJson()`, `factory RateTarget.fromJson(Map<String, dynamic>)`
  - `class RateAlertSettings`
    - 필드: `daily`(bool), `lastDailyBaseDate`(DateTime?), `targets`(List<RateTarget>)
    - `static const empty`, getter `isEnabled`
    - 메서드: `copyWith({bool? daily, DateTime? lastDailyBaseDate, List<RateTarget>? targets})`, `toJson()`, `fromJson`
  - `int newTargetId(DateTime now)`, `String formatTargetKrw(double won)`
  - `class RateAlertMessage { notificationId, title, body }`, `class RateAlertOutcome { settings, messages }`
  - `RateAlertOutcome evaluateRateAlerts({required RateAlertSettings settings, required ExchangeRate rate, required CurrencyInfo currency, required DateTime now})`
  - `bool isTargetReached(RateTarget target, double krwPerUnit)`
  - `int dailyNotificationId(String currencyCode)`

- [ ] **Step 1: 설정 모델 테스트 작성** — `test/rate_alert/rate_alert_settings_test.dart`

```dart
import 'package:app/features/rate_alert/domain/rate_alert_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final target = RateTarget(
    id: 123,
    unit: 100,
    targetKrw: 845,
    direction: TargetDirection.below,
    active: false,
    createdAt: DateTime(2026, 10, 11, 9, 30),
    firedAt: DateTime(2026, 10, 12, 11, 10),
  );

  test('표시 단위로 받은 목표를 1단위 기준으로 바꾼다', () {
    expect(target.krwPerUnit, closeTo(8.45, 1e-9));
  });

  test('JSON 왕복 후에도 같은 값이다', () {
    final settings = RateAlertSettings(
      daily: true,
      lastDailyBaseDate: DateTime(2026, 10, 8),
      targets: [target],
    );

    final restored = RateAlertSettings.fromJson(settings.toJson());

    expect(restored.daily, isTrue);
    expect(restored.lastDailyBaseDate, DateTime(2026, 10, 8));
    final t = restored.targets.single;
    expect(t.id, 123);
    expect(t.unit, 100);
    expect(t.targetKrw, 845);
    expect(t.direction, TargetDirection.below);
    expect(t.active, isFalse);
    expect(t.createdAt, DateTime(2026, 10, 11, 9, 30));
    expect(t.firedAt, DateTime(2026, 10, 12, 11, 10));
  });

  test('매일 알림이나 켜진 목표가 하나라도 있으면 켜진 설정이다', () {
    expect(RateAlertSettings.empty.isEnabled, isFalse);
    expect(const RateAlertSettings(daily: true).isEnabled, isTrue);
    expect(RateAlertSettings(targets: [target]).isEnabled, isFalse); // 도달해서 꺼진 목표만 있음
    expect(RateAlertSettings(targets: [target.copyWith(active: true)]).isEnabled, isTrue);
  });

  test('다시 켜면 도달 시각을 지울 수 있다', () {
    final again = target.copyWith(active: true, clearFiredAt: true);
    expect(again.active, isTrue);
    expect(again.firedAt, isNull);
  });

  test('목표 금액 표기는 불필요한 소수를 붙이지 않는다', () {
    expect(formatTargetKrw(850), '850원');
    expect(formatTargetKrw(1339.5), '1,339.5원');
    expect(formatTargetKrw(52.25), '52.25원');
  });

  test('새 목표 id는 안드로이드 알림 id(32비트) 범위다', () {
    final id = newTargetId(DateTime(2026, 10, 11, 9, 30, 15, 123));
    expect(id, greaterThanOrEqualTo(0));
    expect(id, lessThan(1000000000));
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/rate_alert/rate_alert_settings_test.dart`
Expected: FAIL. 컴파일 에러 `Error when reading 'lib/features/rate_alert/domain/rate_alert_settings.dart'`가 나야 한다.

- [ ] **Step 3: 설정 모델 구현** — `lib/features/rate_alert/domain/rate_alert_settings.dart`

```dart
import 'package:intl/intl.dart';

/// 목표 환율 방향. 기본은 "이하로 내려가면"(싸게 환전하려는 경우가 대부분이다).
enum TargetDirection {
  below('BELOW', '이하'),
  above('ABOVE', '이상');

  const TargetDirection(this.code, this.labelKo);

  final String code;
  final String labelKo;

  static TargetDirection fromCode(String code) =>
      values.firstWhere((d) => d.code == code, orElse: () => below);
}

/// 목표 환율 하나(설계 §6.2). 사용자가 본 그대로 "100엔당 845원"을 [unit]·[targetKrw]로 저장한다 —
/// 나중에 환율이 바뀌어 표시 단위가 달라져도 목록에는 입력한 모양 그대로 보이게 하기 위해서다.
class RateTarget {
  const RateTarget({
    required this.id,
    required this.unit,
    required this.targetKrw,
    required this.direction,
    required this.active,
    required this.createdAt,
    this.firedAt,
  });

  /// 알림 id로도 쓴다(목표마다 알림 하나).
  final int id;

  /// 표시 단위 수량(1, 100, 1000).
  final int unit;

  /// [unit]당 목표 원화.
  final double targetKrw;
  final TargetDirection direction;

  /// false면 감시하지 않는다(도달해서 꺼졌거나 사용자가 껐다).
  final bool active;
  final DateTime createdAt;

  /// 도달해서 알림을 보낸 시각.
  final DateTime? firedAt;

  /// 1단위 기준 목표 원화(설계 §6.2 "1단위 기준으로 바꿔 저장").
  double get krwPerUnit => targetKrw / unit;

  RateTarget copyWith({bool? active, DateTime? firedAt, bool clearFiredAt = false}) => RateTarget(
        id: id,
        unit: unit,
        targetKrw: targetKrw,
        direction: direction,
        active: active ?? this.active,
        createdAt: createdAt,
        firedAt: clearFiredAt ? null : (firedAt ?? this.firedAt),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'unit': unit,
        'targetKrw': targetKrw,
        'direction': direction.code,
        'active': active,
        'createdAt': createdAt.toIso8601String(),
        'firedAt': firedAt?.toIso8601String(),
      };

  factory RateTarget.fromJson(Map<String, dynamic> json) => RateTarget(
        id: json['id'] as int,
        unit: json['unit'] as int,
        targetKrw: (json['targetKrw'] as num).toDouble(),
        direction: TargetDirection.fromCode(json['direction'] as String),
        active: json['active'] as bool,
        createdAt: DateTime.parse(json['createdAt'] as String),
        firedAt: json['firedAt'] == null ? null : DateTime.parse(json['firedAt'] as String),
      );
}

/// 통화 하나의 알림 설정(설계 §6.2).
class RateAlertSettings {
  const RateAlertSettings({this.daily = false, this.lastDailyBaseDate, this.targets = const []});

  static const empty = RateAlertSettings();

  /// 매일 등락 알림.
  final bool daily;

  /// 등락 알림을 마지막으로 보낸 고시일. 같은 고시일로 두 번 보내지 않기 위해 둔다.
  final DateTime? lastDailyBaseDate;
  final List<RateTarget> targets;

  /// 백그라운드 작업이 이 통화를 감시해야 하는가.
  bool get isEnabled => daily || targets.any((t) => t.active);

  RateAlertSettings copyWith({bool? daily, DateTime? lastDailyBaseDate, List<RateTarget>? targets}) =>
      RateAlertSettings(
        daily: daily ?? this.daily,
        lastDailyBaseDate: lastDailyBaseDate ?? this.lastDailyBaseDate,
        targets: targets ?? this.targets,
      );

  Map<String, dynamic> toJson() => {
        'daily': daily,
        'lastDailyBaseDate': lastDailyBaseDate == null ? null : _isoDate(lastDailyBaseDate!),
        'targets': [for (final t in targets) t.toJson()],
      };

  factory RateAlertSettings.fromJson(Map<String, dynamic> json) => RateAlertSettings(
        daily: json['daily'] as bool? ?? false,
        lastDailyBaseDate: json['lastDailyBaseDate'] == null
            ? null
            : DateTime.parse(json['lastDailyBaseDate'] as String),
        targets: [
          for (final t in (json['targets'] as List<dynamic>? ?? const []))
            RateTarget.fromJson(t as Map<String, dynamic>),
        ],
      );

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 새 목표의 id. 안드로이드 알림 id는 32비트 정수라 10억 미만으로 자른다.
int newTargetId(DateTime now) => now.millisecondsSinceEpoch % 1000000000;

/// 목표 금액 표기: 850 → "850원", 1339.5 → "1,339.5원". 사용자가 입력한 모양에 가깝게 보여준다.
String formatTargetKrw(double won) => '${NumberFormat('#,##0.##', 'en_US').format(won)}원';
```

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/rate_alert/rate_alert_settings_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: 판단 로직 테스트 작성** — `test/rate_alert/rate_alert_evaluator_test.dart`

```dart
import 'package:app/features/rate_alert/domain/rate_alert_evaluator.dart';
import 'package:app/features/rate_alert/domain/rate_alert_settings.dart';
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:flutter_test/flutter_test.dart';

ExchangeRate _jpy({double rate = 8.4746, double? previous = 8.4389, DateTime? baseDate}) => ExchangeRate(
      currencyCode: 'JPY',
      krwRate: rate,
      baseDate: baseDate ?? DateTime(2026, 10, 8),
      previousKrwRate: previous,
      previousBaseDate: previous == null ? null : DateTime(2026, 10, 7),
      changePercent: previous == null ? null : 0.42,
      source: 'EXIM',
    );

RateTarget _target({
  int id = 1,
  double krw = 850,
  TargetDirection direction = TargetDirection.below,
  bool active = true,
}) =>
    RateTarget(
      id: id,
      unit: 100,
      targetKrw: krw,
      direction: direction,
      active: active,
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  final jpy = currencyInfoOf('JPY');
  final now = DateTime(2026, 10, 8, 14, 0);

  RateAlertOutcome run(RateAlertSettings settings, {ExchangeRate? rate}) =>
      evaluateRateAlerts(settings: settings, rate: rate ?? _jpy(), currency: jpy, now: now);

  group('전일 대비 알림', () {
    test('새 고시일이고 이전값이 있으면 보내고 고시일을 기록한다', () {
      final outcome = run(const RateAlertSettings(daily: true));

      final message = outcome.messages.single;
      expect(message.title, '환율 등락 알림');
      expect(message.body, '엔화 100엔 847.46원 · 전 영업일보다 ▲3.57원(0.42%)');
      expect(message.notificationId, dailyNotificationId('JPY'));
      expect(outcome.settings.lastDailyBaseDate, DateTime(2026, 10, 8));
    });

    test('하락이면 ▼로 보낸다', () {
      final outcome = run(const RateAlertSettings(daily: true),
          rate: ExchangeRate(
            currencyCode: 'JPY',
            krwRate: 8.4389,
            baseDate: DateTime(2026, 10, 8),
            previousKrwRate: 8.4746,
            changePercent: -0.42,
            source: 'EXIM',
          ));

      expect(outcome.messages.single.body, '엔화 100엔 843.89원 · 전 영업일보다 ▼3.57원(0.42%)');
    });

    test('같은 고시일로는 두 번 보내지 않는다', () {
      final outcome = run(RateAlertSettings(daily: true, lastDailyBaseDate: DateTime(2026, 10, 8)));

      expect(outcome.messages, isEmpty);
    });

    test('이전값이 없으면 보내지 않고 고시일도 기록하지 않는다', () {
      final outcome = run(const RateAlertSettings(daily: true), rate: _jpy(previous: null));

      expect(outcome.messages, isEmpty);
      expect(outcome.settings.lastDailyBaseDate, isNull);
    });

    test('꺼져 있으면 보내지 않는다', () {
      expect(run(RateAlertSettings.empty).messages, isEmpty);
    });
  });

  group('목표 도달 알림', () {
    test('이하 목표는 환율이 목표와 같으면 보낸다(경계값)', () {
      final outcome = run(RateAlertSettings(targets: [_target(krw: 847.46)]));

      final message = outcome.messages.single;
      expect(message.title, '목표 환율 도달');
      expect(message.body, '엔화 100엔 847.46원 (목표 847.46원 이하)');
      expect(message.notificationId, 1);
      final fired = outcome.settings.targets.single;
      expect(fired.active, isFalse);
      expect(fired.firedAt, now);
    });

    test('이상 목표는 환율이 목표와 같으면 보낸다(경계값)', () {
      final outcome = run(RateAlertSettings(
          targets: [_target(krw: 847.46, direction: TargetDirection.above)]));

      expect(outcome.messages.single.body, '엔화 100엔 847.46원 (목표 847.46원 이상)');
    });

    test('도달하지 않으면 보내지 않고 목표도 그대로다', () {
      final outcome = run(RateAlertSettings(targets: [
        _target(krw: 845),
        _target(id: 2, krw: 850, direction: TargetDirection.above),
      ]));

      expect(outcome.messages, isEmpty);
      expect(outcome.settings.targets.every((t) => t.active), isTrue);
    });

    test('꺼진 목표는 조건을 만족해도 무시한다', () {
      final outcome = run(RateAlertSettings(targets: [_target(krw: 850, active: false)]));

      expect(outcome.messages, isEmpty);
      expect(outcome.settings.targets.single.firedAt, isNull);
    });

    test('여러 목표가 동시에 충족되면 모두 보낸다', () {
      final outcome = run(RateAlertSettings(daily: true, targets: [
        _target(id: 1, krw: 850),
        _target(id: 2, krw: 900),
      ]));

      expect(outcome.messages.map((m) => m.notificationId),
          [dailyNotificationId('JPY'), 1, 2]);
      expect(outcome.settings.targets.every((t) => !t.active), isTrue);
    });
  });

  test('isTargetReached는 표시 단위 금액을 전 단위로 비교한다', () {
    final below = _target(krw: 847.46);
    expect(isTargetReached(below, 8.4746), isTrue);
    expect(isTargetReached(below, 8.4747), isFalse);
  });
}
```

- [ ] **Step 6: 실패 확인**

Run: `flutter test test/rate_alert/rate_alert_evaluator_test.dart`
Expected: FAIL. `rate_alert_evaluator.dart` 파일이 없다는 컴파일 에러가 나야 한다.

- [ ] **Step 7: 판단 로직 구현** — `lib/features/rate_alert/domain/rate_alert_evaluator.dart`

```dart
import '../../wallet/data/exchange_rate.dart';
import '../../wallet/domain/currency_info.dart';
import 'rate_alert_settings.dart';

/// 보낼 알림 하나.
class RateAlertMessage {
  const RateAlertMessage({required this.notificationId, required this.title, required this.body});

  /// 같은 id로 다시 보내면 이전 알림을 덮어쓴다(통화별 등락 알림은 하나만 남는다).
  final int notificationId;
  final String title;
  final String body;
}

/// 판단 결과: 저장할 새 설정 + 보낼 알림.
class RateAlertOutcome {
  const RateAlertOutcome({required this.settings, required this.messages});

  final RateAlertSettings settings;
  final List<RateAlertMessage> messages;
}

/// 환율 알림 판단(설계 §6.4). 부수효과가 없는 순수 함수라 백그라운드 작업과 분리해 테스트한다.
///
/// - 전일 대비: 매일 알림이 켜져 있고, 아직 알리지 않은 고시일이며, 이전값이 있을 때 → 고시일 기록
/// - 목표 도달: 켜진 목표가 조건을 만족하면 → 끄고 도달 시각 기록(한 번만 울린다)
RateAlertOutcome evaluateRateAlerts({
  required RateAlertSettings settings,
  required ExchangeRate rate,
  required CurrencyInfo currency,
  required DateTime now,
}) {
  final messages = <RateAlertMessage>[];

  var lastDaily = settings.lastDailyBaseDate;
  final previous = rate.previousKrwRate;
  if (settings.daily && previous != null && !_sameDate(rate.baseDate, lastDaily)) {
    messages.add(_dailyMessage(rate, previous, currency));
    lastDaily = rate.baseDate;
  }

  final targets = <RateTarget>[];
  for (final t in settings.targets) {
    if (t.active && isTargetReached(t, rate.krwRate)) {
      targets.add(t.copyWith(active: false, firedAt: now));
      messages.add(_targetMessage(t, rate, currency));
    } else {
      targets.add(t);
    }
  }

  return RateAlertOutcome(
    settings: settings.copyWith(lastDailyBaseDate: lastDaily, targets: targets),
    messages: messages,
  );
}

/// 목표 도달 여부. 표시 단위 금액(예: 100엔당 847.46원)을 전(0.01원) 단위 정수로 반올림해 비교한다 —
/// 실수끼리 바로 비교하면 8.4746 × 100이 847.4599…가 되어 "같을 때 발송"이 깨진다.
bool isTargetReached(RateTarget target, double krwPerUnit) {
  final current = _cents(krwPerUnit * target.unit);
  final goal = _cents(target.targetKrw);
  return target.direction == TargetDirection.below ? current <= goal : current >= goal;
}

/// 통화별 등락 알림 id. 목표 알림 id(10억 미만)와 겹치지 않게 10억대를 쓴다.
/// String.hashCode는 실행마다 같다는 보장이 없어 직접 계산한다.
int dailyNotificationId(String currencyCode) {
  var hash = 0;
  for (final c in currencyCode.toUpperCase().codeUnits) {
    hash = (hash * 31 + c) % 100000;
  }
  return 1000000000 + hash;
}

int _cents(double won) => (won * 100).round();

bool _sameDate(DateTime a, DateTime? b) =>
    b != null && a.year == b.year && a.month == b.month && a.day == b.day;

RateAlertMessage _dailyMessage(ExchangeRate rate, double previous, CurrencyInfo currency) {
  final unit = currency.displayUnit(rate.krwRate);
  final head = '${currency.nameKo} ${currency.unitLabel(unit)} ${formatKrwRate(unit * rate.krwRate)}';
  final diff = unit * (rate.krwRate - previous);
  final percent = rate.changePercent ?? (rate.krwRate - previous) / previous * 100;
  final String tail;
  if (_cents(diff) == 0) {
    tail = '전 영업일과 같아요';
  } else {
    final arrow = diff > 0 ? '▲' : '▼';
    tail = '전 영업일보다 $arrow${formatKrwRate(diff.abs())}(${percent.abs().toStringAsFixed(2)}%)';
  }
  return RateAlertMessage(
    notificationId: dailyNotificationId(currency.code),
    title: '환율 등락 알림',
    body: '$head · $tail',
  );
}

RateAlertMessage _targetMessage(RateTarget target, ExchangeRate rate, CurrencyInfo currency) {
  final now = formatKrwRate(target.unit * rate.krwRate);
  return RateAlertMessage(
    notificationId: target.id,
    title: '목표 환율 도달',
    body: '${currency.nameKo} ${currency.unitLabel(target.unit)} $now '
        '(목표 ${formatTargetKrw(target.targetKrw)} ${target.direction.labelKo})',
  );
}
```

- [ ] **Step 8: 통과 확인**

Run: `flutter test test/rate_alert/ && dart analyze`
Expected: PASS (17 tests), `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add lib/features/rate_alert/domain test/rate_alert/rate_alert_settings_test.dart test/rate_alert/rate_alert_evaluator_test.dart
git commit -m "feat(app): 환율 알림 설정 모델과 판단 로직 추가"
```

---

### Task 2: 알림 설정 저장소

**Files:**
- Create: `lib/features/rate_alert/data/rate_alert_store.dart`
- Test: `test/rate_alert/rate_alert_store_test.dart`

**Interfaces:**
- Consumes:
  - Task 1의 `RateAlertSettings`(`toJson`/`fromJson`/`isEnabled`/`empty`)
  - 기존 `sharedPreferencesProvider`(`lib/core/prefs/shared_preferences_provider.dart`)
- Produces:
  - `class RateAlertStore`
    - `RateAlertStore(SharedPreferences prefs)`, `static const key = 'rateAlerts.v1'`
    - `Future<Map<String, RateAlertSettings>> readAll()`
    - `Future<RateAlertSettings> read(String currencyCode)`
    - `Future<void> save(String currencyCode, RateAlertSettings settings)`
    - `Future<bool> anyEnabled()`
  - `final rateAlertStoreProvider = Provider<RateAlertStore>`
  - `final rateAlertSettingsProvider = FutureProvider.family<RateAlertSettings, String>` (인자는 통화 코드)

- [ ] **Step 1: 테스트 작성** — `test/rate_alert/rate_alert_store_test.dart`

```dart
import 'package:app/features/rate_alert/data/rate_alert_store.dart';
import 'package:app/features/rate_alert/domain/rate_alert_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late RateAlertStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = RateAlertStore(await SharedPreferences.getInstance());
  });

  final target = RateTarget(
    id: 7,
    unit: 100,
    targetKrw: 845,
    direction: TargetDirection.below,
    active: true,
    createdAt: DateTime(2026, 10, 11),
  );

  test('저장한 적 없는 통화는 빈 설정이다', () async {
    expect((await store.read('JPY')).isEnabled, isFalse);
    expect(await store.readAll(), isEmpty);
    expect(await store.anyEnabled(), isFalse);
  });

  test('통화별로 저장하고 다시 읽는다(코드는 대문자로 맞춘다)', () async {
    await store.save('jpy', RateAlertSettings(targets: [target]));
    await store.save('USD', const RateAlertSettings(daily: true));

    final jpy = await store.read('JPY');
    expect(jpy.targets.single.krwPerUnit, closeTo(8.45, 1e-9));
    expect((await store.read('usd')).daily, isTrue);
    expect((await store.readAll()).keys, containsAll(['JPY', 'USD']));
  });

  test('한 통화를 저장해도 다른 통화 설정은 그대로다', () async {
    await store.save('USD', const RateAlertSettings(daily: true));
    await store.save('JPY', RateAlertSettings(targets: [target]));
    await store.save('JPY', RateAlertSettings.empty);

    expect((await store.read('USD')).daily, isTrue);
    expect((await store.read('JPY')).targets, isEmpty);
  });

  test('켜진 알림이 하나라도 있는지 알려준다', () async {
    await store.save('JPY', RateAlertSettings(targets: [target.copyWith(active: false)]));
    expect(await store.anyEnabled(), isFalse);

    await store.save('USD', const RateAlertSettings(daily: true));
    expect(await store.anyEnabled(), isTrue);
  });

  test('깨진 값은 빈 설정으로 읽는다', () async {
    SharedPreferences.setMockInitialValues({RateAlertStore.key: '{not json'});
    store = RateAlertStore(await SharedPreferences.getInstance());

    expect(await store.readAll(), isEmpty);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/rate_alert/rate_alert_store_test.dart`
Expected: FAIL. `rate_alert_store.dart` 파일이 없다는 컴파일 에러가 나야 한다.

- [ ] **Step 3: 구현** — `lib/features/rate_alert/data/rate_alert_store.dart`

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../domain/rate_alert_settings.dart';

/// 통화별 환율 알림 설정을 기기에 저장한다(설계 §6.2, 키 `rateAlerts.v1`).
///
/// 화면(앱 isolate)과 백그라운드 작업(WorkManager isolate)이 같은 값을 읽고 쓴다.
/// SharedPreferences는 isolate마다 메모리 캐시를 따로 두므로, 읽기 전에 항상 `reload()`로
/// 디스크 값을 다시 가져온다 — 그래야 화면이 백그라운드가 기록한 "도달함"을 옛 값으로 덮어쓰지 않는다.
class RateAlertStore {
  RateAlertStore(this._prefs);

  final SharedPreferences _prefs;

  static const key = 'rateAlerts.v1';

  Future<Map<String, RateAlertSettings>> readAll() async {
    await _prefs.reload();
    final raw = _prefs.getString(key);
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in json.entries) e.key: RateAlertSettings.fromJson(e.value as Map<String, dynamic>),
      };
    } on FormatException {
      return {}; // 깨진 값은 없는 것으로 보고, 다음 저장 때 덮어쓴다.
    } on TypeError {
      return {};
    }
  }

  Future<RateAlertSettings> read(String currencyCode) async =>
      (await readAll())[currencyCode.toUpperCase()] ?? RateAlertSettings.empty;

  /// 한 통화만 바꾼다. 저장 직전에 전체를 다시 읽어 다른 통화의 최신 값을 보존한다.
  Future<void> save(String currencyCode, RateAlertSettings settings) async {
    final all = await readAll();
    all[currencyCode.toUpperCase()] = settings;
    await _prefs.setString(key, jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}));
  }

  /// 백그라운드 작업을 등록해 둘지 판단할 때 쓴다.
  Future<bool> anyEnabled() async => (await readAll()).values.any((s) => s.isEnabled);
}

final rateAlertStoreProvider = Provider<RateAlertStore>((ref) {
  return RateAlertStore(ref.watch(sharedPreferencesProvider));
});

/// 통화 코드별 알림 설정. 화면에서 바꾼 뒤에는 이 프로바이더를 invalidate 한다.
final rateAlertSettingsProvider = FutureProvider.family<RateAlertSettings, String>((ref, currencyCode) {
  return ref.watch(rateAlertStoreProvider).read(currencyCode);
});
```

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/rate_alert/ && dart analyze`
Expected: PASS (22 tests), `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/rate_alert/data test/rate_alert/rate_alert_store_test.dart
git commit -m "feat(app): 환율 알림 설정 저장소 추가"
```

---

### Task 3: 알림 발송·권한·작업 등록 (플랫폼 연결)

**Files:**
- Modify: `pubspec.yaml`(+ `pubspec.lock`) — `flutter_local_notifications: ^22.3.1`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/build.gradle.kts`
- Create: `lib/features/rate_alert/notify/rate_notifier.dart`
- Create: `lib/features/rate_alert/notify/notification_permission.dart`
- Create: `lib/features/rate_alert/background/rate_alert_scheduler.dart`

**Interfaces:**
- Consumes: Task 1의 `RateAlertMessage`(`notificationId`, `title`, `body`)
- Produces:
  - `abstract interface class RateNotifier { Future<void> show(RateAlertMessage message); }`
  - `class LocalRateNotifier implements RateNotifier`
  - `abstract interface class NotificationPermission { Future<bool> request(); }`
  - `class PermissionHandlerNotificationPermission implements NotificationPermission`
  - `final notificationPermissionProvider = Provider<NotificationPermission>`
  - `const rateAlertTaskName = 'com.travelfootsteps.rateAlert'`
  - `abstract interface class RateAlertScheduler { Future<void> sync({required bool enabled}); }`
  - `class WorkmanagerRateAlertScheduler implements RateAlertScheduler`
  - `final rateAlertSchedulerProvider = Provider<RateAlertScheduler>`

이 태스크의 세 구현체는 실제 플랫폼을 호출하는 얇은 껍데기라 단위 테스트를 두지 않는다. 검증은 두 가지다. Task 4·5가 인터페이스를 가짜로 바꿔 동작을 테스트하고, 이 태스크에서는 APK 빌드가 성공하는지 확인한다.

- [ ] **Step 1: 의존성 추가**

Run: `flutter pub add flutter_local_notifications:^22.3.1`
Expected: `pubspec.yaml`의 dependencies에 `flutter_local_notifications: ^22.3.1`이 추가된다. 오류 없이 `Changed N dependencies!`가 나와야 한다.

- [ ] **Step 2: 매니페스트에 알림 권한 추가** — `android/app/src/main/AndroidManifest.xml`

기존 `<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />` 줄 바로 아래에 추가한다:

```xml
    <!-- Android 13+ 알림 표시 권한(환율 알림). 처음 알림을 켤 때 앱에서 요청한다. -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

- [ ] **Step 3: desugaring 켜기** — `android/app/build.gradle.kts`

flutter_local_notifications 10+는 core library desugaring을 요구한다(플러그인 README "Gradle setup"). `compileOptions` 블록을 다음처럼 바꾼다:

```kotlin
    compileOptions {
        // flutter_local_notifications가 요구한다(java.time 등 최신 API를 옛 안드로이드에서도 쓰게 해 준다).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
```

파일 끝 `dependencies { … }` 블록의 마지막 `implementation(...)` 줄 아래에 추가한다:

```kotlin
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
```

- [ ] **Step 4: 알림 발송 구현** — `lib/features/rate_alert/notify/rate_notifier.dart`

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/rate_alert_evaluator.dart';

/// 환율 알림을 띄우는 쪽(설계 §6.5). 백그라운드 작업 테스트가 가짜로 바꿀 수 있게 인터페이스로 둔다.
abstract interface class RateNotifier {
  Future<void> show(RateAlertMessage message);
}

/// flutter_local_notifications로 기기 알림을 띄운다. 알림을 누르면 앱이 열린다(플러그인 기본 동작).
/// 백그라운드 isolate에서도 쓰므로 처음 보낼 때 스스로 초기화한다.
class LocalRateNotifier implements RateNotifier {
  LocalRateNotifier([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const channelId = 'rate_alerts';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      '환율 알림',
      channelDescription: '전 영업일 대비 등락과 목표 환율 도달 알림',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  @override
  Future<void> show(RateAlertMessage message) async {
    await _ensureInitialized();
    await _plugin.show(
      id: message.notificationId,
      title: message.title,
      body: message.body,
      notificationDetails: _details,
    );
  }
}
```

- [ ] **Step 5: 권한 요청 구현** — `lib/features/rate_alert/notify/notification_permission.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// 알림 권한 요청(설계 §6.5). 화면 테스트에서 허용/거부를 흉내 낼 수 있게 인터페이스로 둔다.
abstract interface class NotificationPermission {
  /// 허용돼 있거나 이번에 허용하면 true. Android 12 이하는 런타임 권한이 없어 항상 true다.
  Future<bool> request();
}

class PermissionHandlerNotificationPermission implements NotificationPermission {
  const PermissionHandlerNotificationPermission();

  @override
  Future<bool> request() async => (await Permission.notification.request()).isGranted;
}

final notificationPermissionProvider = Provider<NotificationPermission>((ref) {
  return const PermissionHandlerNotificationPermission();
});
```

- [ ] **Step 6: 작업 등록 구현** — `lib/features/rate_alert/background/rate_alert_scheduler.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

/// WorkManager 작업 이름. 발걸음 작업(com.travelfootsteps.footstepCheckin)과 같은 규칙.
const rateAlertTaskName = 'com.travelfootsteps.rateAlert';

/// 환율 알림 백그라운드 작업 등록/취소(설계 §6.3).
abstract interface class RateAlertScheduler {
  /// [enabled]면 3시간 주기 작업을 등록하고(이미 있으면 그대로 둔다), 아니면 취소한다.
  Future<void> sync({required bool enabled});
}

class WorkmanagerRateAlertScheduler implements RateAlertScheduler {
  const WorkmanagerRateAlertScheduler();

  @override
  Future<void> sync({required bool enabled}) {
    if (!enabled) return Workmanager().cancelByUniqueName(rateAlertTaskName);
    return Workmanager().registerPeriodicTask(
      rateAlertTaskName,
      rateAlertTaskName,
      // 고시 환율은 하루 1회 바뀌지만, 고시 시각(11시경)이 지나면 몇 시간 안에 알리려고 3시간마다 확인한다.
      frequency: const Duration(hours: 3),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }
}

final rateAlertSchedulerProvider = Provider<RateAlertScheduler>((ref) {
  return const WorkmanagerRateAlertScheduler();
});
```

- [ ] **Step 7: 분석·테스트·빌드 확인**

Run: `dart analyze && flutter test`
Expected: `No issues found!`, 전체 테스트 통과 (269 + 22)

Run: `flutter build apk --debug` (몇 분 걸린다. Bash 타임아웃은 600000ms)
Expected: `√ Built build\app\outputs\flutter-apk\app-debug.apk`. desugaring 설정이 빠지면 여기서 `requires core library desugaring to be enabled`로 실패한다.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml android/app/build.gradle.kts lib/features/rate_alert/notify lib/features/rate_alert/background/rate_alert_scheduler.dart
git commit -m "feat(app): 환율 알림 발송·권한·백그라운드 작업 등록 연결"
```

---

### Task 4: 공용 백그라운드 디스패처와 환율 알림 작업

**Files:**
- Create: `lib/features/rate_alert/background/rate_alert_task.dart`
- Create: `lib/core/background/app_callback_dispatcher.dart`
- Modify: `lib/features/footsteps/background/footstep_workmanager.dart`
- Modify: `lib/main.dart`
- Test: `test/rate_alert/rate_alert_task_test.dart`
- Test: `test/core/background/app_callback_dispatcher_test.dart`

**Interfaces:**
- Consumes:
  - Task 1의 `evaluateRateAlerts`, `RateAlertMessage`
  - Task 2의 `RateAlertStore`(`readAll`, `save`)
  - Task 3의 `RateNotifier`, `LocalRateNotifier`, `rateAlertTaskName`
  - 기존 `ExchangeRateApi(Dio)`.`getRate(String)`, `RateCache(SharedPreferences)`.`write(String, RateSnapshot)`, `RateSnapshot(rate:, fetchedAt:)`, `currencyInfoOf`, `resolveBaseUrl({required bool isAndroid})`(`lib/core/network/api_client.dart`)
- Produces:
  - `Future<bool> handleRateAlertTask({required RateAlertStore store, required ExchangeRateApi api, required RateCache cache, required RateNotifier notifier, required DateTime Function() now})`
  - `Future<bool> runRateAlertTask()`
  - `Future<bool> runFootstepTask()` (기존 `footstepCallbackDispatcher` 대체)
  - `typedef BackgroundTaskRunner = Future<bool> Function()`
  - `Future<bool> dispatchBackgroundTask(String taskName, Map<String, BackgroundTaskRunner> runners)`
  - `void appCallbackDispatcher()`, `Future<void> initializeBackgroundWork()`

- [ ] **Step 1: 작업 핸들러 테스트 작성** — `test/rate_alert/rate_alert_task_test.dart`

```dart
import 'package:app/features/rate_alert/background/rate_alert_task.dart';
import 'package:app/features/rate_alert/data/rate_alert_store.dart';
import 'package:app/features/rate_alert/domain/rate_alert_evaluator.dart';
import 'package:app/features/rate_alert/domain/rate_alert_settings.dart';
import 'package:app/features/rate_alert/notify/rate_notifier.dart';
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/exchange_rate_api.dart';
import 'package:app/features/wallet/data/rate_cache.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi implements ExchangeRateApi {
  _FakeApi(this.rates, {this.fail = false});

  final Map<String, ExchangeRate> rates;
  final bool fail;
  final requested = <String>[];

  @override
  Future<ExchangeRate> getRate(String currencyCode) async {
    requested.add(currencyCode);
    if (fail) throw DioException(requestOptions: RequestOptions(path: '/api/exchange-rates/$currencyCode'));
    return rates[currencyCode]!;
  }
}

class _FakeNotifier implements RateNotifier {
  final shown = <RateAlertMessage>[];

  @override
  Future<void> show(RateAlertMessage message) async => shown.add(message);
}

final _jpyRate = ExchangeRate(
  currencyCode: 'JPY',
  krwRate: 8.4746,
  baseDate: DateTime(2026, 10, 8),
  previousKrwRate: 8.4389,
  previousBaseDate: DateTime(2026, 10, 7),
  changePercent: 0.42,
  source: 'EXIM',
);

void main() {
  late SharedPreferences prefs;
  late RateAlertStore store;
  late RateCache cache;
  late _FakeNotifier notifier;
  final now = DateTime(2026, 10, 8, 14);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = RateAlertStore(prefs);
    cache = RateCache(prefs);
    notifier = _FakeNotifier();
  });

  final target = RateTarget(
    id: 5,
    unit: 100,
    targetKrw: 850,
    direction: TargetDirection.below,
    active: true,
    createdAt: DateTime(2026, 10, 1),
  );

  test('켜진 통화의 환율을 받아 캐시를 갱신하고, 알림을 보내고, 바뀐 설정을 저장한다', () async {
    await store.save('JPY', RateAlertSettings(daily: true, targets: [target]));
    final api = _FakeApi({'JPY': _jpyRate});

    final result = await handleRateAlertTask(
        store: store, api: api, cache: cache, notifier: notifier, now: () => now);

    expect(result, isTrue);
    expect(notifier.shown.map((m) => m.title), ['환율 등락 알림', '목표 환율 도달']);
    expect(cache.read('JPY')!.rate.krwRate, 8.4746);
    expect(cache.read('JPY')!.fetchedAt, now);
    final saved = await store.read('JPY');
    expect(saved.lastDailyBaseDate, DateTime(2026, 10, 8));
    expect(saved.targets.single.active, isFalse);
    expect(saved.targets.single.firedAt, now);
  });

  test('다시 돌려도 같은 알림을 또 보내지 않는다', () async {
    await store.save('JPY', RateAlertSettings(daily: true, targets: [target]));
    final api = _FakeApi({'JPY': _jpyRate});

    await handleRateAlertTask(store: store, api: api, cache: cache, notifier: notifier, now: () => now);
    await handleRateAlertTask(store: store, api: api, cache: cache, notifier: notifier, now: () => now);

    expect(notifier.shown, hasLength(2));
  });

  test('꺼진 통화는 조회하지 않는다', () async {
    await store.save('USD', RateAlertSettings(targets: [target.copyWith(active: false)]));
    await store.save('JPY', const RateAlertSettings(daily: true));
    final api = _FakeApi({'JPY': _jpyRate});

    await handleRateAlertTask(store: store, api: api, cache: cache, notifier: notifier, now: () => now);

    expect(api.requested, ['JPY']);
  });

  test('서버 조회가 실패하면 알림도 없고 설정도 그대로다', () async {
    await store.save('JPY', RateAlertSettings(daily: true, targets: [target]));
    final api = _FakeApi({}, fail: true);

    final result = await handleRateAlertTask(
        store: store, api: api, cache: cache, notifier: notifier, now: () => now);

    expect(result, isTrue); // 실패로 돌려 WorkManager가 곧바로 재시도하게 하지 않는다 — 3시간 뒤 다시 본다.
    expect(notifier.shown, isEmpty);
    expect(cache.read('JPY'), isNull);
    final saved = await store.read('JPY');
    expect(saved.lastDailyBaseDate, isNull);
    expect(saved.targets.single.active, isTrue);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/rate_alert/rate_alert_task_test.dart`
Expected: FAIL. `rate_alert_task.dart` 파일이 없다는 컴파일 에러가 나야 한다.

- [ ] **Step 3: 작업 핸들러 구현** — `lib/features/rate_alert/background/rate_alert_task.dart`

```dart
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../wallet/data/exchange_rate.dart';
import '../../wallet/data/exchange_rate_api.dart';
import '../../wallet/data/rate_cache.dart';
import '../../wallet/domain/currency_info.dart';
import '../data/rate_alert_store.dart';
import '../domain/rate_alert_evaluator.dart';
import '../notify/rate_notifier.dart';

/// 환율 알림 작업 한 번(설계 §6.3): 설정 읽기 → 켜진 통화마다 서버 조회 → 지갑 환율 캐시 갱신
/// → 판단 → 알림 → 바뀐 설정 저장.
///
/// 한 통화의 조회가 실패해도 다른 통화는 계속 본다. 실패한 통화는 설정을 건드리지 않으므로
/// 다음 주기(3시간 뒤)에 다시 판단한다. 그래서 항상 true(성공)를 돌려준다.
Future<bool> handleRateAlertTask({
  required RateAlertStore store,
  required ExchangeRateApi api,
  required RateCache cache,
  required RateNotifier notifier,
  required DateTime Function() now,
}) async {
  final all = await store.readAll();
  for (final entry in all.entries) {
    if (!entry.value.isEnabled) continue;
    final code = entry.key;

    final ExchangeRate rate;
    try {
      rate = await api.getRate(code);
    } catch (_) {
      continue;
    }
    final fetchedAt = now();
    // 지갑의 "몇 시간마다 원화 가치 갱신"은 이 캐시를 통해 이뤄진다(설계 §1-3, §6.3).
    await cache.write(code, RateSnapshot(rate: rate, fetchedAt: fetchedAt));

    final outcome = evaluateRateAlerts(
      settings: entry.value,
      rate: rate,
      currency: currencyInfoOf(code),
      now: fetchedAt,
    );
    for (final message in outcome.messages) {
      await notifier.show(message);
    }
    if (outcome.messages.isNotEmpty) {
      await store.save(code, outcome.settings);
    }
  }
  return true;
}

/// WorkManager isolate에서 실제 의존성을 만들어 [handleRateAlertTask]를 돌린다.
/// 이 isolate에는 Riverpod도 Firebase도 없다 — 환율 API는 로그인 없이 열려 있으므로(1단계 SecurityConfig)
/// 토큰 없는 Dio로 충분하다.
Future<bool> runRateAlertTask() async {
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(
    baseUrl: resolveBaseUrl(isAndroid: Platform.isAndroid),
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
  return handleRateAlertTask(
    store: RateAlertStore(prefs),
    api: ExchangeRateApi(dio),
    cache: RateCache(prefs),
    notifier: LocalRateNotifier(),
    now: DateTime.now,
  );
}
```

- [ ] **Step 4: 작업 핸들러 통과 확인**

Run: `flutter test test/rate_alert/rate_alert_task_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: 디스패처 테스트 작성** — `test/core/background/app_callback_dispatcher_test.dart`

```dart
import 'package:app/core/background/app_callback_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('작업 이름에 맞는 함수만 실행하고 그 결과를 돌려준다', () async {
    final ran = <String>[];
    final runners = <String, BackgroundTaskRunner>{
      'footstep': () async {
        ran.add('footstep');
        return true;
      },
      'rate': () async {
        ran.add('rate');
        return false;
      },
    };

    expect(await dispatchBackgroundTask('rate', runners), isFalse);
    expect(ran, ['rate']);
  });

  test('모르는 작업 이름은 아무것도 하지 않고 성공으로 끝낸다', () async {
    final ran = <String>[];

    final result = await dispatchBackgroundTask('old.task', {
      'footstep': () async {
        ran.add('footstep');
        return true;
      },
    });

    expect(result, isTrue);
    expect(ran, isEmpty);
  });
}
```

- [ ] **Step 6: 실패 확인**

Run: `flutter test test/core/background/app_callback_dispatcher_test.dart`
Expected: FAIL. `app_callback_dispatcher.dart` 파일이 없다는 컴파일 에러가 나야 한다.

- [ ] **Step 7: 발걸음 작업을 실행 함수로 바꾼다** — `lib/features/footsteps/background/footstep_workmanager.dart`

파일 전체를 아래로 바꾼다. 발걸음 로직(저장소·위치 설정)은 그대로이고, 디스패처와 `initialize` 호출만 공용 디스패처로 옮긴다(설계 §6.6). WorkManager는 앱 전체에 콜백 디스패처를 하나만 둘 수 있기 때문이다.

```dart
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/db/app_database.dart';
import '../data/footsteps_repository.dart';
import '../data/geocoding_country_resolver.dart';
import 'footstep_task_handler.dart';

const footstepTaskName = 'com.travelfootsteps.footstepCheckin';

/// 발걸음 체크인 작업 한 번. 공용 디스패처(core/background/app_callback_dispatcher.dart)가
/// WorkManager isolate에서 부른다. Riverpod 컨테이너에 접근할 수 없으므로 의존성을 직접 만든다.
Future<bool> runFootstepTask() async {
  final db = AppDatabase();
  final repository = FootstepsRepository(
    db: db,
    countryResolver: GeocodingCountryResolver(),
  );

  await handleFootstepTask(
    repository: repository,
    getCurrentPosition: () => Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        // 개발/테스트는 에뮬레이터로 진행 중 — .medium은 raw GPS를 켜지 않아
        // 에뮬레이터 주입 좌표가 전달되지 않는다. 실기기 배포 전 .medium으로 되돌릴 것.
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    ),
  );

  await db.close();
  return true;
}

/// 앱 시작 시 1회 호출한다(그 전에 `initializeBackgroundWork()`가 끝나 있어야 한다).
/// 이미 등록돼 있으면 `existingWorkPolicy`가 중복 등록을 막는다.
void registerFootstepBackgroundTask() {
  Workmanager().registerPeriodicTask(
    footstepTaskName,
    footstepTaskName,
    frequency: const Duration(hours: 1),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.notRequired),
  );
}
```

- [ ] **Step 8: 공용 디스패처 구현** — `lib/core/background/app_callback_dispatcher.dart`

```dart
import 'package:workmanager/workmanager.dart';

import '../../features/footsteps/background/footstep_workmanager.dart';
import '../../features/rate_alert/background/rate_alert_scheduler.dart';
import '../../features/rate_alert/background/rate_alert_task.dart';

typedef BackgroundTaskRunner = Future<bool> Function();

/// 작업 이름으로 실행할 함수를 고른다. 모르는 이름(예전 버전이 등록한 작업 등)은
/// 성공(true)으로 끝내 WorkManager가 재시도하지 않게 한다.
Future<bool> dispatchBackgroundTask(String taskName, Map<String, BackgroundTaskRunner> runners) {
  final runner = runners[taskName];
  return runner == null ? Future.value(true) : runner();
}

/// WorkManager가 별도 isolate에서 호출하는 top-level 콜백. 앱 전체에 하나만 둘 수 있어
/// 발걸음·환율 알림 작업을 여기서 나눈다(설계 §6.6).
@pragma('vm:entry-point')
void appCallbackDispatcher() {
  Workmanager().executeTask((taskName, _) => dispatchBackgroundTask(taskName, {
        footstepTaskName: runFootstepTask,
        rateAlertTaskName: runRateAlertTask,
      }));
}

/// 앱 시작 시 작업을 등록하기 전에 한 번 부른다.
Future<void> initializeBackgroundWork() => Workmanager().initialize(appCallbackDispatcher);
```

- [ ] **Step 9: main에서 공용 디스패처를 초기화** — `lib/main.dart`

import 목록에 추가한다(알파벳 순서상 `core/auth/auth_providers.dart` 위):

```dart
import 'core/background/app_callback_dispatcher.dart';
```

`registerFootstepBackgroundTask();` 줄을 다음 두 줄로 바꾼다:

```dart
  await initializeBackgroundWork();
  registerFootstepBackgroundTask();
```

- [ ] **Step 10: 통과 확인**

Run: `dart analyze && flutter test`
Expected: `No issues found!`. 전체 테스트가 통과해야 한다(Task 3 이후 개수 + 6).

- [ ] **Step 11: Commit**

```bash
git add lib/features/rate_alert/background/rate_alert_task.dart lib/core/background lib/features/footsteps/background/footstep_workmanager.dart lib/main.dart test/rate_alert/rate_alert_task_test.dart test/core/background
git commit -m "feat(app): 공용 백그라운드 디스패처와 환율 알림 작업 추가"
```

---

### Task 5: 환율 알림 화면과 라우트

**Files:**
- Create: `lib/features/wallet/widgets/sub_page_header.dart`
- Modify: `lib/features/wallet/wallet_page.dart` (`_WalletHeader` → `SubPageHeader`)
- Create: `lib/features/rate_alert/rate_alert_page.dart`
- Modify: `lib/router.dart`
- Test: `test/rate_alert/rate_alert_page_test.dart`

**Interfaces:**
- Consumes:
  - Task 1의 `RateAlertSettings`, `RateTarget`, `TargetDirection`, `newTargetId`, `formatTargetKrw`, `isTargetReached`
  - Task 2의 `rateAlertStoreProvider`, `rateAlertSettingsProvider`
  - Task 3의 `notificationPermissionProvider`, `rateAlertSchedulerProvider`, `NotificationPermission`, `RateAlertScheduler`
  - 기존 위젯과 데이터:
    - `RateBanner(currency:, snapshot:)`, `walletRateProvider`, `countryDetailProvider`(→ `CountryDetail.nameKo`, `currencyCode`)
    - `currencyInfoOf`, `formatMonthDay`
    - `SectionLabel`, `FilterPill`, `PillButton`, `AppColors`, `AppTextStyles`
- Produces:
  - `class SubPageHeader extends StatelessWidget { const SubPageHeader({super.key, required String title, Widget? trailing}); }`
  - `class RateAlertPage extends ConsumerStatefulWidget { const RateAlertPage({super.key, required String isoAlpha2}); }`
  - `AppRoutes.rateAlert = '/checklist/rate-alert'`, `static String AppRoutes.rateAlertOf(String isoAlpha2)`
  - 위젯 키:
    - `dailySwitch`, `targetAmountField`, `addTargetButton`
    - `direction_BELOW`, `direction_ABOVE`
    - `targetSwitch_<id>`, `deleteTarget_<id>`

- [ ] **Step 1: 공용 헤더 추출** — `lib/features/wallet/widgets/sub_page_header.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// 탭 아래 상세 화면의 헤더(뒤로가기 + 제목 + 오른쪽 메뉴). 지갑과 환율 알림 화면이 같이 쓴다.
class SubPageHeader extends StatelessWidget {
  const SubPageHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textBody),
            onPressed: () => context.pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: AppTextStyles.screenTitle, overflow: TextOverflow.ellipsis),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
```

(`?trailing`은 Dart 3.8+ null-aware 요소다. pubspec SDK는 `^3.13.2`라 쓸 수 있다.)

- [ ] **Step 2: 지갑 헤더가 공용 헤더를 쓰게 바꾼다** — `lib/features/wallet/wallet_page.dart`

`class _WalletHeader extends StatelessWidget { … }` 전체(현재 `build`가 `Container(height: 54, …)`를 돌려주는 클래스)를 아래로 바꾼다. 키·문구·동작은 같다:

```dart
class _WalletHeader extends StatelessWidget {
  const _WalletHeader({required this.title, this.onClear});

  final String title;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return SubPageHeader(
      title: title,
      trailing: onClear == null
          ? null
          : PopupMenuButton<String>(
              key: const Key('walletMenu'),
              icon: const Icon(Icons.more_vert, color: AppColors.textBody),
              onSelected: (_) => onClear!(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'clear', child: Text('지갑 비우기')),
              ],
            ),
    );
  }
}
```

import에 `import 'widgets/sub_page_header.dart';`를 추가한다. 이제 안 쓰이는 `package:go_router/go_router.dart` import가 생기면 `dart analyze`가 알려 주는 대로 지운다.

Run: `flutter test test/wallet/`
Expected: PASS (62 tests, 변경 전과 같음)

- [ ] **Step 3: 화면 테스트 작성** — `test/rate_alert/rate_alert_page_test.dart`

```dart
import 'dart:convert';

import 'package:app/core/network/country_detail_api.dart';
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/rate_alert/background/rate_alert_scheduler.dart';
import 'package:app/features/rate_alert/data/rate_alert_store.dart';
import 'package:app/features/rate_alert/domain/rate_alert_settings.dart';
import 'package:app/features/rate_alert/notify/notification_permission.dart';
import 'package:app/features/rate_alert/rate_alert_page.dart';
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/wallet_rate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../wallet/wallet_fixtures.dart';

class _FakePermission implements NotificationPermission {
  _FakePermission(this.granted);

  final bool granted;
  int requests = 0;

  @override
  Future<bool> request() async {
    requests++;
    return granted;
  }
}

class _FakeScheduler implements RateAlertScheduler {
  final calls = <bool>[];

  @override
  Future<void> sync({required bool enabled}) async => calls.add(enabled);
}

class _Harness {
  _Harness(this.store, this.permission, this.scheduler);

  final RateAlertStore store;
  final _FakePermission permission;
  final _FakeScheduler scheduler;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool granted = true,
  RateSnapshot? rate,
  bool withRate = true,
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  final permission = _FakePermission(granted);
  final scheduler = _FakeScheduler();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      countryDetailProvider.overrideWith((ref, iso) async => const CountryDetail(
            isoAlpha2: 'JP',
            nameKo: '일본',
            currencyCode: 'JPY',
            cardAcceptance: 'MEDIUM',
          )),
      walletRateProvider.overrideWith(
          (ref, code) => Stream<RateSnapshot?>.value(withRate ? (rate ?? snapshot()) : null)),
      notificationPermissionProvider.overrideWithValue(permission),
      rateAlertSchedulerProvider.overrideWithValue(scheduler),
    ],
    child: const MaterialApp(home: Scaffold(body: RateAlertPage(isoAlpha2: 'JP'))),
  ));
  await tester.pumpAndSettle();
  return _Harness(RateAlertStore(prefs), permission, scheduler);
}

Future<void> _addTarget(WidgetTester tester, String amount, {TargetDirection? direction}) async {
  if (direction != null) {
    await tester.ensureVisible(find.byKey(Key('direction_${direction.code}')));
    await tester.tap(find.byKey(Key('direction_${direction.code}')));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.byKey(const Key('targetAmountField')));
  await tester.enterText(find.byKey(const Key('targetAmountField')), amount);
  await tester.ensureVisible(find.byKey(const Key('addTargetButton')));
  await tester.tap(find.byKey(const Key('addTargetButton')));
  await tester.pumpAndSettle();
}

bool _switchValue(WidgetTester tester, String key) =>
    tester.widget<Switch>(find.byKey(Key(key))).value;

void main() {
  testWidgets('제목·환율 배너·빈 목표 안내·꺼진 매일 알림을 보여준다', (tester) async {
    await _pump(tester);

    expect(find.text('일본 환율 알림'), findsOneWidget);
    expect(find.text('100엔 = 847.46원'), findsOneWidget);
    expect(find.text('아직 목표가 없습니다.'), findsOneWidget);
    expect(find.text('100엔당 목표 환율'), findsOneWidget);
    expect(_switchValue(tester, 'dailySwitch'), isFalse);
  });

  testWidgets('목표를 추가하면 목록에 보이고, 1단위 기준으로 저장되고, 작업이 등록된다', (tester) async {
    final h = await _pump(tester);

    await _addTarget(tester, '845');

    expect(find.text('100엔당 845원 이하'), findsOneWidget);
    expect(find.text('대기 중'), findsOneWidget);
    expect(find.text('현재 환율이 이미 목표에 도달했어요'), findsNothing);
    final saved = (await h.store.read('JPY')).targets.single;
    expect(saved.krwPerUnit, closeTo(8.45, 1e-9));
    expect(saved.active, isTrue);
    expect(h.scheduler.calls.last, isTrue);
  });

  testWidgets('이미 도달한 목표를 저장하면 바로 알려준다', (tester) async {
    await _pump(tester);

    await _addTarget(tester, '840', direction: TargetDirection.above);

    expect(find.text('100엔당 840원 이상'), findsOneWidget);
    expect(find.text('현재 환율이 이미 목표에 도달했어요'), findsOneWidget);
  });

  testWidgets('금액이 잘못되면 저장하지 않고 안내한다', (tester) async {
    final h = await _pump(tester);

    await _addTarget(tester, '0');

    expect(find.text('금액을 확인해 주세요'), findsOneWidget);
    expect((await h.store.read('JPY')).targets, isEmpty);
    expect(h.permission.requests, 0);
  });

  testWidgets('알림 권한을 거부하면 매일 알림 스위치가 꺼진 채로 남고 안내한다', (tester) async {
    final h = await _pump(tester, granted: false);

    await tester.tap(find.byKey(const Key('dailySwitch')));
    await tester.pumpAndSettle();

    expect(_switchValue(tester, 'dailySwitch'), isFalse);
    expect(find.text('알림 권한이 꺼져 있어 환율 알림을 켤 수 없어요. 설정에서 알림을 허용해 주세요.'),
        findsOneWidget);
    expect((await h.store.read('JPY')).daily, isFalse);
    expect(h.scheduler.calls, isEmpty);
  });

  testWidgets('매일 알림을 켜면 작업을 등록하고, 끄면 취소한다', (tester) async {
    final h = await _pump(tester);

    await tester.tap(find.byKey(const Key('dailySwitch')));
    await tester.pumpAndSettle();
    expect(_switchValue(tester, 'dailySwitch'), isTrue);
    expect(h.scheduler.calls, [true]);

    await tester.tap(find.byKey(const Key('dailySwitch')));
    await tester.pumpAndSettle();
    expect(_switchValue(tester, 'dailySwitch'), isFalse);
    expect(h.scheduler.calls, [true, false]);
    expect(h.permission.requests, 1); // 끌 때는 권한을 묻지 않는다
  });

  testWidgets('도달한 목표는 회색 상태로 보이고, 다시 켜거나 삭제할 수 있다', (tester) async {
    final fired = RateTarget(
      id: 9,
      unit: 100,
      targetKrw: 850,
      direction: TargetDirection.below,
      active: false,
      createdAt: DateTime(2026, 10, 1),
      firedAt: DateTime(2026, 10, 8, 14),
    );
    final h = await _pump(tester, initialPrefs: {
      RateAlertStore.key: jsonEncode({'JPY': RateAlertSettings(targets: [fired]).toJson()}),
    });

    expect(find.text('도달 · 10월 8일'), findsOneWidget);
    expect(_switchValue(tester, 'targetSwitch_9'), isFalse);

    await tester.tap(find.byKey(const Key('targetSwitch_9')));
    await tester.pumpAndSettle();
    final again = (await h.store.read('JPY')).targets.single;
    expect(again.active, isTrue);
    expect(again.firedAt, isNull);
    expect(find.text('대기 중'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deleteTarget_9')));
    await tester.pumpAndSettle();
    expect((await h.store.read('JPY')).targets, isEmpty);
    expect(find.text('아직 목표가 없습니다.'), findsOneWidget);
    expect(h.scheduler.calls.last, isFalse);
  });

  testWidgets('환율을 모르면 목표 추가 폼 대신 안내를 보여준다', (tester) async {
    await _pump(tester, withRate: false);

    expect(find.byKey(const Key('targetAmountField')), findsNothing);
    expect(find.text('환율 정보를 받은 뒤에 목표를 추가할 수 있어요.'), findsOneWidget);
  });
}
```

- [ ] **Step 4: 실패 확인**

Run: `flutter test test/rate_alert/rate_alert_page_test.dart`
Expected: FAIL. `rate_alert_page.dart` 파일이 없다는 컴파일 에러가 나야 한다.

- [ ] **Step 5: 화면 구현** — `lib/features/rate_alert/rate_alert_page.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/country_detail_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../wallet/data/exchange_rate.dart';
import '../wallet/data/wallet_rate.dart';
import '../wallet/domain/currency_info.dart';
import '../wallet/domain/month_day.dart';
import '../wallet/widgets/rate_banner.dart';
import '../wallet/widgets/sub_page_header.dart';
import 'background/rate_alert_scheduler.dart';
import 'data/rate_alert_store.dart';
import 'domain/rate_alert_evaluator.dart';
import 'domain/rate_alert_settings.dart';
import 'notify/notification_permission.dart';

/// 환율 알림 설정 화면 — 지갑·환율 알림 설계 §6.1.
/// 준비물 탭 환전 섹션의 `환율 알림 ›`에서 `/checklist/rate-alert?iso=JP`로 들어온다.
class RateAlertPage extends ConsumerStatefulWidget {
  const RateAlertPage({super.key, required this.isoAlpha2});

  final String isoAlpha2;

  @override
  ConsumerState<RateAlertPage> createState() => _RateAlertPageState();
}

class _RateAlertPageState extends ConsumerState<RateAlertPage> {
  final _amount = TextEditingController();
  TargetDirection _direction = TargetDirection.below;
  String? _amountError;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(countryDetailProvider(widget.isoAlpha2));
    return detailAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Notice(title: '환율 알림', message: '국가 정보를 불러오지 못했습니다: $e'),
      data: (detail) {
        final code = detail.currencyCode?.trim();
        if (code == null || code.isEmpty) {
          return _Notice(
            title: '${detail.nameKo} 환율 알림',
            message: '이 나라의 통화 정보가 없어 환율 알림을 쓸 수 없습니다.',
          );
        }
        return _page(detail, currencyInfoOf(code));
      },
    );
  }

  Widget _page(CountryDetail detail, CurrencyInfo currency) {
    final snapshot = ref.watch(walletRateProvider(currency.code)).value;
    final settings = ref.watch(rateAlertSettingsProvider(currency.code)).value;

    return Column(
      children: [
        SubPageHeader(title: '${detail.nameKo} 환율 알림'),
        Expanded(
          child: settings == null
              ? const Center(child: CircularProgressIndicator())
              // 배너의 "아래로 당겨 다시 시도" 안내가 지갑과 똑같이 동작하게 한다.
              : RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(walletRateProvider(currency.code));
                    await ref.read(walletRateProvider(currency.code).future);
                  },
                  child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  children: [
                    RateBanner(currency: currency, snapshot: snapshot),
                    const SizedBox(height: 18),
                    const SectionLabel('등락 알림'),
                    const SizedBox(height: 4),
                    _DailyRow(
                      value: settings.daily,
                      onChanged: (on) => _setDaily(currency.code, on),
                    ),
                    const SizedBox(height: 18),
                    const SectionLabel('목표 환율'),
                    const SizedBox(height: 4),
                    if (settings.targets.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('아직 목표가 없습니다.', style: AppTextStyles.caption),
                      ),
                    for (final t in settings.targets)
                      _TargetRow(
                        currency: currency,
                        target: t,
                        onToggle: (on) => _toggleTarget(currency.code, t.id, on),
                        onDelete: () => _deleteTarget(currency.code, t.id),
                      ),
                    const SizedBox(height: 16),
                    if (snapshot == null)
                      Text('환율 정보를 받은 뒤에 목표를 추가할 수 있어요.', style: AppTextStyles.caption)
                    else
                      _addForm(currency, snapshot.rate),
                  ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _addForm(CurrencyInfo currency, ExchangeRate rate) {
    final unit = currency.displayUnit(rate.krwRate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterPill(
              key: const Key('direction_BELOW'),
              label: '이하로 내려가면',
              selected: _direction == TargetDirection.below,
              onTap: () => setState(() => _direction = TargetDirection.below),
            ),
            FilterPill(
              key: const Key('direction_ABOVE'),
              label: '이상으로 오르면',
              selected: _direction == TargetDirection.above,
              onTap: () => setState(() => _direction = TargetDirection.above),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('targetAmountField'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '${currency.unitLabel(unit)}당 목표 환율',
            hintText: '지금 ${formatKrwRate(unit * rate.krwRate)}',
            suffixText: '원',
            errorText: _amountError,
          ),
        ),
        const SizedBox(height: 12),
        PillButton(
          key: const Key('addTargetButton'),
          label: '목표 추가',
          onPressed: () => _addTarget(currency.code, unit, rate),
        ),
      ],
    );
  }

  /// 알림을 켜는 동작 전에 권한을 받는다. 거부되면 저장하지 않으므로 스위치는 원래 값으로 남는다.
  Future<bool> _ensurePermission() async {
    final granted = await ref.read(notificationPermissionProvider).request();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('알림 권한이 꺼져 있어 환율 알림을 켤 수 없어요. 설정에서 알림을 허용해 주세요.'),
      ));
    }
    return granted;
  }

  /// 저장소의 최신 값에 [change]를 적용해 저장하고, 켜진 알림 유무에 맞춰 백그라운드 작업을 등록/취소한다.
  /// 화면이 들고 있던 값이 아니라 저장소를 다시 읽어 바꾸는 이유: 그 사이 백그라운드 작업이
  /// "도달함"이나 마지막 등락 알림 고시일을 기록했을 수 있다.
  Future<void> _update(String code, RateAlertSettings Function(RateAlertSettings) change) async {
    final store = ref.read(rateAlertStoreProvider);
    final scheduler = ref.read(rateAlertSchedulerProvider);
    await store.save(code, change(await store.read(code)));
    await scheduler.sync(enabled: await store.anyEnabled());
    if (mounted) ref.invalidate(rateAlertSettingsProvider(code));
  }

  Future<void> _setDaily(String code, bool on) async {
    if (on && !await _ensurePermission()) return;
    if (!mounted) return;
    await _update(code, (s) => s.copyWith(daily: on));
  }

  Future<void> _addTarget(String code, int unit, ExchangeRate rate) async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (amount == null || amount <= 0) {
      setState(() => _amountError = '금액을 확인해 주세요');
      return;
    }
    setState(() => _amountError = null);
    if (!await _ensurePermission() || !mounted) return;

    final now = DateTime.now();
    final target = RateTarget(
      id: newTargetId(now),
      unit: unit,
      targetKrw: amount,
      direction: _direction,
      active: true,
      createdAt: now,
    );
    await _update(code, (s) => s.copyWith(targets: [...s.targets, target]));
    if (!mounted) return;
    _amount.clear();
    if (isTargetReached(target, rate.krwRate)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('현재 환율이 이미 목표에 도달했어요')));
    }
  }

  /// 다시 켜면 도달 기록을 지워 처음부터 감시한다.
  Future<void> _toggleTarget(String code, int id, bool on) async {
    if (on && !await _ensurePermission()) return;
    if (!mounted) return;
    await _update(
      code,
      (s) => s.copyWith(targets: [
        for (final t in s.targets)
          if (t.id != id) t else if (on) t.copyWith(active: true, clearFiredAt: true) else t.copyWith(active: false),
      ]),
    );
  }

  Future<void> _deleteTarget(String code, int id) =>
      _update(code, (s) => s.copyWith(targets: [for (final t in s.targets) if (t.id != id) t]));
}

class _DailyRow extends StatelessWidget {
  const _DailyRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('매일 등락 알림', style: AppTextStyles.body),
              const SizedBox(height: 2),
              Text('새 고시 환율이 나오면 전 영업일 대비 등락을 알려줘요', style: AppTextStyles.caption),
            ],
          ),
        ),
        Switch(key: const Key('dailySwitch'), value: value, onChanged: onChanged),
      ],
    );
  }
}

/// 목표 한 줄. 꺼진 목표(도달했거나 사용자가 끔)는 회색으로 보인다.
class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.currency,
    required this.target,
    required this.onToggle,
    required this.onDelete,
  });

  final CurrencyInfo currency;
  final RateTarget target;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = target;
    final String status;
    if (t.active) {
      status = '대기 중';
    } else if (t.firedAt != null) {
      status = '도달 · ${formatMonthDay(t.firedAt!)}';
    } else {
      status = '꺼짐';
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${currency.unitLabel(t.unit)}당 ${formatTargetKrw(t.targetKrw)} ${t.direction.labelKo}',
                  style: AppTextStyles.body.copyWith(
                    color: t.active ? AppColors.ink : AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(status, style: AppTextStyles.caption),
              ],
            ),
          ),
          Switch(key: Key('targetSwitch_${t.id}'), value: t.active, onChanged: onToggle),
          IconButton(
            key: Key('deleteTarget_${t.id}'),
            icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SubPageHeader(title: title),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(message, style: AppTextStyles.caption, textAlign: TextAlign.center),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: 라우트 추가** — `lib/router.dart`

import에 추가한다(`features/wallet/wallet_page.dart` import 위):

```dart
import 'features/rate_alert/rate_alert_page.dart';
```

`AppRoutes`의 `walletOf` 아래에 추가한다:

```dart
  /// 환율 알림 설정. 준비물 탭 환전 섹션에서 들어오며, 지갑처럼 준비물 탭이 켜진 채로 둔다.
  static const rateAlert = '/checklist/rate-alert';

  static String rateAlertOf(String isoAlpha2) => '$rateAlert?iso=$isoAlpha2';
```

`ShellRoute.routes`의 지갑 `GoRoute` 바로 아래에 추가한다:

```dart
          GoRoute(
            path: AppRoutes.rateAlert,
            builder: (_, state) =>
                RateAlertPage(isoAlpha2: state.uri.queryParameters['iso'] ?? 'VN'),
          ),
```

- [ ] **Step 7: 통과 확인**

Run: `flutter test test/rate_alert/ test/wallet/ test/router_test.dart && dart analyze`
Expected: 모든 테스트 PASS(rate_alert_page_test 8개 포함), `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/features/wallet/widgets/sub_page_header.dart lib/features/wallet/wallet_page.dart lib/features/rate_alert/rate_alert_page.dart lib/router.dart test/rate_alert/rate_alert_page_test.dart
git commit -m "feat(app): 환율 알림 설정 화면과 라우트 추가"
```

---

### Task 6: 준비물 탭 환전 섹션에 `환율 알림 ›` 연결

**Files:**
- Modify: `lib/features/checklist/checklist_page.dart`
- Test: `test/checklist/checklist_page_test.dart`

**Interfaces:**
- Consumes: Task 5의 `AppRoutes.rateAlertOf(String)`
- Produces: 위젯 키 `rateAlertLink`

- [ ] **Step 1: 테스트 수정·추가** — `test/checklist/checklist_page_test.dart`

`_pumpChecklist`의 `GoRouter.routes`에서 지갑 `GoRoute` 아래에 추가한다:

```dart
      GoRoute(
        path: '/checklist/rate-alert',
        builder: (_, state) => Scaffold(body: Text('rate-alert ${state.uri.queryParameters['iso']}')),
      ),
```

`main()` 끝에 테스트를 추가한다:

```dart
  testWidgets('환전 섹션 끝에 환율 알림 행이 있고, 누르면 그 나라 환율 알림으로 간다', (tester) async {
    await _pumpChecklist(tester);

    expect(find.byKey(const Key('rateAlertLink')), findsOneWidget);
    expect(find.text('환율 알림'), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget); // 체크 항목 수에는 들어가지 않는다

    await tester.ensureVisible(find.byKey(const Key('rateAlertLink')));
    await tester.tap(find.byKey(const Key('rateAlertLink')));
    await tester.pumpAndSettle();

    expect(find.text('rate-alert VN'), findsOneWidget);
  });
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/checklist/checklist_page_test.dart`
Expected: 새 테스트만 FAIL(`rateAlertLink`를 찾지 못함)하고, 기존 2개는 PASS해야 한다.

- [ ] **Step 3: 구현** — `lib/features/checklist/checklist_page.dart`

`_buildSections`를 아래로 바꾼다. 바뀌는 점은 두 가지다. 환전(`MONEY`) 섹션의 마지막 항목 뒤에 링크 행을 넣고, 환전 섹션이 없는 나라면 목록 끝에 환전 섹션을 만들어 링크를 넣는다:

```dart
  /// 카테고리별로 묶어서 SectionLabel + 항목들을 순서대로 만든다.
  /// 서버가 priority 오름차순으로 이미 정렬해서 주므로, 처음 등장하는 순서 그대로
  /// 섹션을 나눈다. 환전 섹션 끝에는 환율 알림 설정으로 가는 행을 붙인다(지갑·환율 알림 설계 §6.1).
  List<Widget> _buildSections(List<ChecklistItem> items, Set<int> checkedIds) {
    final widgets = <Widget>[];
    String? currentCategory;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.category != currentCategory) {
        currentCategory = item.category;
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 14));
        widgets.add(SectionLabel(item.categoryLabelKo));
        widgets.add(const SizedBox(height: 4));
      }
      widgets.add(_ChecklistRow(
        checked: checkedIds.contains(item.id),
        label: item.title,
        description: item.description,
        onTap: () => _toggleChecked(item.id),
      ));
      final lastOfMoney = item.category == _moneyCategory &&
          (i == items.length - 1 || items[i + 1].category != _moneyCategory);
      if (lastOfMoney) widgets.add(_RateAlertLink(onTap: _openRateAlert));
    }

    if (widgets.isEmpty) {
      widgets.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('이 나라에 등록된 준비물이 아직 없습니다.'),
      ));
    } else if (!items.any((i) => i.category == _moneyCategory)) {
      widgets
        ..add(const SizedBox(height: 14))
        ..add(const SectionLabel('환전'))
        ..add(const SizedBox(height: 4))
        ..add(_RateAlertLink(onTap: _openRateAlert));
    }
    return widgets;
  }

  static const _moneyCategory = 'MONEY';

  void _openRateAlert() => context.push(AppRoutes.rateAlertOf(_isoAlpha2));
```

파일 끝(`_AddManuallyRow` 클래스 위)에 행 위젯을 추가한다:

```dart
/// 환전 섹션 끝의 `환율 알림 ›` 행. 체크 항목이 아니라 설정 화면으로 가는 링크다.
class _RateAlertLink extends StatelessWidget {
  const _RateAlertLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('rateAlertLink'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
        ),
        child: Row(
          children: [
            const Icon(Icons.notifications_none, size: 20, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('환율 알림', style: AppTextStyles.body.copyWith(color: AppColors.accent)),
                  const SizedBox(height: 2),
                  Text('등락 알림·목표 환율 도달 알림 설정', style: AppTextStyles.caption),
                ],
              ),
            ),
            Text('›', style: AppTextStyles.cardTitle.copyWith(color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 통과 확인**

Run: `dart analyze && flutter test`
Expected: `No issues found!`, 전체 테스트 PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/checklist/checklist_page.dart test/checklist/checklist_page_test.dart
git commit -m "feat(app): 준비물 환전 섹션에 환율 알림 설정 연결"
```

---

### Task 7: 실기기 확인

코드는 바꾸지 않는다. 서버를 띄운 상태에서 실제 폰으로 알림까지 받아 본다.

- [ ] **Step 1: 서버 기동과 연결**
  1. `server/`에서 `./gradlew bootRun`을 실행한다. 로그에 `Started ServerApplication`이 나와야 한다.
  2. `adb reverse tcp:8080 tcp:8080`으로 폰을 PC 서버에 연결한다.
- [ ] **Step 2: 앱 실행**: `app/`에서 `flutter run --dart-define=API_BASE_URL=http://localhost:8080`
- [ ] **Step 3: 확인 목록** (모두 통과해야 3단계 완료)
  1. 준비물 탭 환전 섹션 끝에 `환율 알림 ›` 행이 있고, 누르면 `{나라} 환율 알림` 화면이 열린다. 아래 탭바는 준비물 탭에 그대로 있다.
  2. 화면 위에 지갑과 같은 환율 배너가 보인다.
  3. 처음 무언가를 켜면 안드로이드 알림 권한 창이 뜬다. 거부하면 스위치가 꺼진 채로 남고 안내가 나온다. 다시 시도하려면 설정 → 앱 → 알림에서 허용한다.
  4. 현재 환율보다 높은 금액으로 `이하로 내려가면` 목표를 추가하면 "현재 환율이 이미 목표에 도달했어요"가 나온다. 1~2분 안에 `목표 환율 도달` 알림이 오고, 목표가 `도달 · {오늘}`로 회색이 된다. 화면에 다시 들어가면 바뀐 상태가 보인다.
     - WorkManager 주기 작업은 처음 등록될 때 한 번 바로 실행된다.
     - 이미 등록돼 있다면 모든 알림을 끈 뒤(작업 취소) 다시 켜면 다시 등록되면서 바로 실행된다.
  5. `매일 등락 알림`을 켜면 같은 방식으로 `환율 등락 알림`이 온다. 문구는 `엔화 100엔 …원 · 전 영업일보다 ▲/▼…원(…%)` 형식이다.
  6. 알림을 누르면 앱이 열린다.
  7. 도달한 목표를 다시 켜면 `대기 중`이 된다. 삭제하면 목록에서 사라진다.
  8. 모든 알림을 끄면 작업이 취소된다. `adb shell dumpsys jobscheduler | findstr rateAlert` 결과에 등록된 작업이 없어야 한다.
  9. 발걸음 기록(1시간 주기 체크인)이 이전처럼 동작한다. 공용 디스패처 전환 후 회귀가 없어야 한다.

---

## Self-Review

- **§6.1 설정 UI**
  - 진입: Task 6
  - 배너 재사용: Task 5 `RateBanner`
  - 매일 스위치: Task 5 `_DailyRow`
  - 목표 목록·추가 폼(표시 단위, 이하 기본/이상): Task 5
  - 도달 목표 회색·다시 켜기·삭제: Task 5 `_TargetRow`, `_toggleTarget`, `_deleteTarget`
  - "이미 도달" 즉시 안내: Task 5 `_addTarget`
- **§6.2 저장**
  - `rateAlerts.v1`, 통화별 `{daily, lastDailyBaseDate, targets}`: Task 1·2
  - 1단위 변환: `krwPerUnit`
  - 표시 모양 보존을 위해 `unit`을 함께 저장하는 것은 의도된 확장이다.
- **§6.3 백그라운드**
  - 3시간·네트워크 조건, 켜짐/꺼짐에 따른 등록/취소: Task 3 스케줄러 + Task 5 `_update`
  - 실행 순서(설정 → 조회 → 캐시 → 판단 → 알림 → 저장): Task 4 `handleRateAlertTask`
- **§6.4 판단**
  - 전일 대비(중복 방지·이전값 없음), 목표(경계값 포함·한 번만): Task 1
  - 문구: Global Constraints와 Task 1 테스트
- **§6.5 알림·권한**
  - `RateNotifier` + 채널 `rate_alerts`: Task 3
  - `POST_NOTIFICATIONS` + `permission_handler` 요청 + 거부 시 원복: Task 3·5
- **§6.6 공용 디스패처**: Task 4. 발걸음 로직은 바꾸지 않고 실행 함수로만 옮겼다.
- **§6.7 테스트**
  - Evaluator: Task 1
  - Store 왕복·변환: Task 1·2
  - 작업 핸들러(캐시·발송·실패 시 불변): Task 4
  - 디스패처(분기·모르는 이름 true): Task 4
  - 화면(추가·이미 도달·권한 거부 원복): Task 5
- **타입 일관성:** 아래 이름과 인자는 정의한 태스크와 쓰는 태스크에서 같다.
  - 설정 모델: `RateAlertSettings`, `RateTarget`, `TargetDirection`
  - 판단 함수: `evaluateRateAlerts`, `isTargetReached`, `dailyNotificationId`, `RateAlertMessage`
  - 저장소: `RateAlertStore.read/save/readAll/anyEnabled`, `rateAlertStoreProvider`, `rateAlertSettingsProvider`
  - 알림·권한·작업 등록: `RateNotifier.show`, `NotificationPermission.request`, `RateAlertScheduler.sync({required bool enabled})`, `rateAlertTaskName`
  - 백그라운드: `handleRateAlertTask`, `runRateAlertTask`, `runFootstepTask`, `dispatchBackgroundTask`
  - 화면·라우트: `SubPageHeader`, `AppRoutes.rateAlertOf`
