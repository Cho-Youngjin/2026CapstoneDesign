# 지갑 2단계 — 앱 지갑(여행 가계부) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 준비물 탭의 `지갑` 카드에서 나라별 지갑을 열어 지출(식비·숙박·교통·관광·기타)과 환전을 기록하고, 환율 배너와 남은 돈의 원화 가치를 본다.

**Architecture:** `app/lib/features/wallet/` 아래에 순수 규칙(통화·카테고리·합계·목록 정렬), 데이터(서버 환율 API + 기기 캐시, 별도 drift DB `wallet.sqlite`), 위젯(배너·남은 돈 카드·목록·바텀시트 폼), 화면(`WalletPage`)을 층으로 나눈다. 금액은 통화 최소단위 정수로만 저장·계산한다. 준비물 탭의 세 번째 카드를 `지갑`으로 바꾸고, 보조배터리 정보는 체크리스트 행으로 옮긴다.

**Tech Stack:** Flutter, Riverpod 3.4(flutter_riverpod), go_router 18, dio 5, drift 2.35 + drift_dev/build_runner, shared_preferences, intl 0.20, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-09-wallet-exchange-alerts-design.md` §5. 서버 계약은 1단계(`GET /api/exchange-rates/{code}`, 토큰 없이 200)를 쓴다.

## Global Constraints

- 작업 브랜치는 `wallet`. 커밋 메시지에 `Co-Authored-By`·Claude·AI 관련 트레일러를 절대 넣지 않는다.
- 모든 명령은 `app/` 디렉터리에서 실행한다. 정적 분석은 **`dart analyze`** 를 쓴다(`flutter analyze`는 이 PC의 한글 경로 때문에 죽는다 — 코드 문제가 아님). 테스트는 `flutter test <파일>`.
- drift 코드 생성은 **`dart run build_runner build --delete-conflicting-outputs --force-jit`** 로만 한다(`--force-jit` 없이는 한글 경로에서 AOT 단계가 실패한다). 생성 후 팀원 소유 파일의 줄바꿈 변경을 되돌린다: `git checkout -- lib/core/db/app_database.g.dart`. 생성된 `wallet_database.g.dart`는 커밋한다.
- 발걸음 기능의 `AppDatabase`(`lib/core/db/app_database.dart`)는 수정하지 않는다. 지갑은 별도 DB 파일 `wallet.sqlite`.
- 금액은 **통화 최소단위 정수**(`int`)로 저장·합산한다. 원화 환산은 `(최소단위 / 10^소수자릿수) × 1단위당원화`를 `round()`한 정수 원. 소수 자릿수: JPY·VND·IDR 0, 그 외 표의 통화 2.
- 환율 표시 단위: `{1, 100, 1000}` 중 `단위 × 1단위 환율 ≥ 10원`인 가장 작은 값(USD 1, JPY 100, VND 1000).
- 디자인: 기존 토큰(`AppColors`, `AppTextStyles`)과 공용 위젯(`WireframeCard`, `PillButton`, `PillOutlineButton`, `FilterPill`, `SectionLabel`)만 쓴다. 그림자 없음. 상승은 `AppColors.warn`, 하락은 `AppColors.accent`.
- 서버 응답(1단계 계약): `{"currencyCode":"JPY","krwRate":8.4746,"baseDate":"2026-10-08","previousKrwRate":8.491,"previousBaseDate":"2026-10-07","changePercent":-0.19,"source":"EXIM"}`. `source`는 `"EXIM"` 또는 `"ER_API"`, 이전값 세 필드는 null 가능.
- Riverpod 3: 패밀리 프로바이더 테스트 덮어쓰기는 `xxxProvider.overrideWith((ref, arg) => ...)`. `AsyncValue.value`는 nullable(로딩·오류면 null). `StateProvider`가 필요하면 `package:flutter_riverpod/legacy.dart`(이 계획은 쓰지 않는다).
- 화면 문구(정확히): 배너 `100엔 = 847.46원`, `▲ 0.42%`/`▼ 0.31%`, `10월 8일 고시 · 한국수출입은행`, `10월 9일 기준 · 참고환율 · Rates By Exchange Rate API`, `환율 정보 없음 · 아래로 당겨 다시 시도`. 카드 `남은 돈`, `환전 ¥50,000 · 지출 ¥17,600`, `환전 평가손익 +3,730원`. 기타 메모 힌트 `여행자보험, eSIM 등`.
- 앱 코드 주석은 기존 파일처럼 한국어 문서 주석으로 "왜"를 짧게 남긴다(서버의 Spring 학습 주석 규칙은 앱에 적용하지 않는다).
- `dart analyze`가 `prefer_const_constructors`·`prefer_const_literals_to_create_immutables` 같은 스타일 info를 내면, 계획의 코드에 `const`를 붙이는 식으로 **동작을 바꾸지 않고** 해결해 `No issues found!`를 맞춘다. 문구·값·키·로직은 바꾸지 않는다.

## File Structure

| 파일 | 상태 | 책임 |
|---|---|---|
| `lib/features/wallet/domain/currency_info.dart` | 생성 | 통화 표(기호·한글명·소수자릿수), 입력 파싱, 금액·원화 포맷, 표시 단위 |
| `lib/features/wallet/domain/expense_category.dart` | 생성 | 지출 카테고리 5종(코드·라벨·메모 힌트) |
| `lib/features/wallet/domain/month_day.dart` | 생성 | `10월 9일` 날짜 표기 |
| `lib/features/wallet/data/exchange_rate.dart` | 생성 | 서버 환율 응답 모델 `ExchangeRate`, 캐시 단위 `RateSnapshot` |
| `lib/features/wallet/data/exchange_rate_api.dart` | 생성 | `GET /api/exchange-rates/{code}` 호출 |
| `lib/features/wallet/data/rate_cache.dart` | 생성 | `shared_preferences`의 `rateCache.<CUR>` 읽기/쓰기 |
| `lib/features/wallet/data/wallet_rate.dart` | 생성 | 캐시 먼저 → 서버 갱신 스트림, `walletRateProvider` |
| `lib/features/wallet/data/wallet_database.dart` (+ `.g.dart`) | 생성 | drift `Expenses`·`Exchanges`, CRUD·감시·지갑 비우기, 스트림 프로바이더 |
| `lib/features/wallet/domain/wallet_summary.dart` | 생성 | 환전·지출·잔액·카테고리 합계·평가손익 |
| `lib/features/wallet/domain/wallet_entries.dart` | 생성 | 지출+환전 목록 정렬·필터·날짜 묶음 |
| `lib/features/wallet/widgets/rate_banner.dart` | 생성 | 환율 배너(3단계 알림 화면도 재사용) |
| `lib/features/wallet/widgets/balance_card.dart` | 생성 | 남은 돈 카드 |
| `lib/features/wallet/widgets/form_date_row.dart` | 생성 | 폼의 날짜 행 |
| `lib/features/wallet/widgets/expense_form_sheet.dart` | 생성 | 지출 기록/수정 바텀시트 |
| `lib/features/wallet/widgets/exchange_form_sheet.dart` | 생성 | 환전 기록/수정 바텀시트 |
| `lib/features/wallet/widgets/wallet_entry_list.dart` | 생성 | 날짜별 기록 목록 |
| `lib/features/wallet/wallet_page.dart` | 생성 | 지갑 화면 조립·기록 추가/수정/삭제/비우기 |
| `lib/router.dart` | 수정 | `/checklist/wallet` 라우트 |
| `lib/features/checklist/data/power_bank_item.dart` | 생성 | 보조배터리 체크리스트 행 생성 |
| `lib/features/checklist/checklist_page.dart` | 수정 | 세 번째 카드 → 지갑, 보조배터리 행 삽입 |
| `test/wallet/*`, `test/checklist/power_bank_item_test.dart`, `test/checklist/checklist_page_test.dart` | 생성 | 각 태스크 테스트 |

---

### Task 1: 통화·카테고리·날짜 표기 규칙

**Files:**
- Create: `app/lib/features/wallet/domain/currency_info.dart`
- Create: `app/lib/features/wallet/domain/expense_category.dart`
- Create: `app/lib/features/wallet/domain/month_day.dart`
- Test: `app/test/wallet/currency_info_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `class CurrencyInfo { String code; int minorDigits; String symbol; String nameKo; String unitKo; int? parseToMinor(String input); double toMajor(int minor); String toInputText(int minor); String format(int minor); int toKrw(int minor, double krwPerUnit); int displayUnit(double krwPerUnit); String unitLabel(int unit); }`
  - `CurrencyInfo currencyInfoOf(String code)`
  - `String formatKrw(int won)`, `String formatKrwRate(double won)`
  - `enum ExpenseCategory { food, lodging, transport, sightseeing, other }` with `String code` (`FOOD`…), `String labelKo`, `String memoHint`, `static ExpenseCategory fromCode(String code)`
  - `String formatMonthDay(DateTime date)`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/wallet/currency_info_test.dart`:

```dart
import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:app/features/wallet/domain/expense_category.dart';
import 'package:app/features/wallet/domain/month_day.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final jpy = currencyInfoOf('JPY');
  final usd = currencyInfoOf('USD');
  final vnd = currencyInfoOf('VND');

  group('CurrencyInfo.parseToMinor', () {
    test('콤마가 섞인 정수 입력을 최소단위로 바꾼다', () {
      expect(jpy.parseToMinor('1,200'), 1200);
      expect(usd.parseToMinor('12.5'), 1250);
      expect(usd.parseToMinor('12'), 1200);
    });

    test('통화보다 소수 자릿수가 많으면 null', () {
      expect(jpy.parseToMinor('12.5'), isNull);
      expect(usd.parseToMinor('12.345'), isNull);
    });

    test('0, 빈 값, 숫자가 아닌 값은 null', () {
      expect(usd.parseToMinor('0'), isNull);
      expect(usd.parseToMinor(''), isNull);
      expect(usd.parseToMinor('abc'), isNull);
      expect(usd.parseToMinor('-3'), isNull);
    });
  });

  group('CurrencyInfo 표시', () {
    test('통화 기호와 천 단위 콤마, 소수 자릿수로 표시한다', () {
      expect(jpy.format(1200), '¥1,200');
      expect(usd.format(1250), r'$12.50');
      expect(vnd.format(-50000), '-₫50,000');
    });

    test('편집 폼에 다시 채울 문자열은 콤마 없이 소수 자릿수를 맞춘다', () {
      expect(usd.toInputText(1250), '12.50');
      expect(jpy.toInputText(1200), '1200');
    });

    test('원화 환산은 반올림한 정수 원이다', () {
      expect(jpy.toKrw(1200, 8.4746), 10170);
      expect(vnd.toKrw(50000, 0.051934), 2597);
    });

    test('표시 단위는 단위×환율이 10원 이상이 되는 가장 작은 값이다', () {
      expect(usd.displayUnit(1339.2), 1);
      expect(jpy.displayUnit(8.4746), 100);
      expect(vnd.displayUnit(0.051934), 1000);
    });

    test('단위 라벨은 수량과 한글 단위를 붙인다', () {
      expect(jpy.unitLabel(100), '100엔');
      expect(vnd.unitLabel(1000), '1,000동');
      expect(usd.unitLabel(1), '1달러');
    });

    test('원화와 환율 값 표기', () {
      expect(formatKrw(10170), '10,170원');
      expect(formatKrw(-500), '-500원');
      expect(formatKrwRate(847.46), '847.46원');
      expect(formatKrwRate(1339.2), '1,339.20원');
    });
  });

  group('currencyInfoOf', () {
    test('소문자 코드도 찾는다', () {
      expect(currencyInfoOf('jpy').code, 'JPY');
    });

    test('표에 없는 통화는 코드로 표시하고 소수 2자리로 다룬다', () {
      final unknown = currencyInfoOf('XYZ');
      expect(unknown.minorDigits, 2);
      expect(unknown.format(150), 'XYZ 1.50');
    });

    test('우리 country 테이블의 통화 17개가 모두 표에 있다', () {
      const codes = ['AUD', 'CAD', 'CHF', 'CNY', 'CZK', 'EUR', 'GBP', 'HKD', 'IDR', 'JPY',
        'PHP', 'SGD', 'THB', 'TRY', 'TWD', 'USD', 'VND'];
      for (final code in codes) {
        // 표에 없으면 대체값의 nameKo가 코드 그대로다. 표의 통화는 모두 한글 이름을 가진다.
        expect(currencyInfoOf(code).nameKo, isNot(code), reason: code);
      }
    });
  });

  group('ExpenseCategory', () {
    test('코드로 찾고, 모르는 코드는 기타로 본다', () {
      expect(ExpenseCategory.fromCode('SIGHTSEEING'), ExpenseCategory.sightseeing);
      expect(ExpenseCategory.fromCode('???'), ExpenseCategory.other);
    });

    test('라벨과 메모 힌트', () {
      expect(ExpenseCategory.values.map((c) => c.labelKo).toList(),
          ['식비', '숙박', '교통', '관광', '기타']);
      expect(ExpenseCategory.other.memoHint, '여행자보험, eSIM 등');
      expect(ExpenseCategory.sightseeing.memoHint, '입장료, 투어 등');
      expect(ExpenseCategory.food.memoHint, '메모 (선택)');
    });
  });

  test('formatMonthDay', () {
    expect(formatMonthDay(DateTime(2026, 10, 9)), '10월 9일');
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/wallet/currency_info_test.dart`
Expected: FAIL — 컴파일 에러(`currency_info.dart` 등 파일 없음)

- [ ] **Step 3: `currency_info.dart` 작성**

`app/lib/features/wallet/domain/currency_info.dart`:

```dart
import 'dart:math' as math;

import 'package:intl/intl.dart';

/// 통화 하나의 표시·계산 규칙.
///
/// 지갑의 금액은 앱 전체에서 "최소단위 정수"(엔은 1엔, 달러는 1센트)로 다루고,
/// 화면에 보일 때만 이 정보로 바꾼다 — 실수(double)로 더하면 0.1 + 0.2 같은 오차가 쌓이기 때문이다.
class CurrencyInfo {
  const CurrencyInfo({
    required this.code,
    required this.minorDigits,
    required this.symbol,
    required this.nameKo,
    required this.unitKo,
  });

  final String code;

  /// 소수 자릿수. 엔·동·루피아는 0, 달러·유로 등은 2.
  final int minorDigits;
  final String symbol;

  /// 알림 문구 등에 쓰는 통화 이름(예: "엔화", "미국 달러").
  final String nameKo;

  /// "100엔", "1달러"처럼 수량 뒤에 붙는 단위.
  final String unitKo;

  int get _scale => math.pow(10, minorDigits).toInt();

  /// "1,200" / "12.5" 같은 입력을 최소단위 정수로 바꾼다.
  /// 형식이 틀리거나, 소수 자릿수가 이 통화보다 많거나, 0 이하면 null.
  int? parseToMinor(String input) {
    final text = input.replaceAll(',', '').trim();
    final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(text);
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final fraction = match.group(2) ?? '';
    if (fraction.length > minorDigits) return null;
    final fractionMinor =
        fraction.isEmpty ? 0 : int.parse(fraction.padRight(minorDigits, '0'));
    final minor = whole * _scale + fractionMinor;
    return minor > 0 ? minor : null;
  }

  double toMajor(int minor) => minor / _scale;

  /// 편집 폼에 다시 채울 문자열(콤마 없음). 예: 1250센트 → "12.50", 1200엔 → "1200".
  String toInputText(int minor) => toMajor(minor).toStringAsFixed(minorDigits);

  /// "¥1,200", "$12.50", "-₫50,000"
  String format(int minor) {
    final pattern = minorDigits == 0 ? '#,##0' : '#,##0.${'0' * minorDigits}';
    final text = NumberFormat(pattern, 'en_US').format(toMajor(minor.abs()));
    return '${minor < 0 ? '-' : ''}$symbol$text';
  }

  /// 원화 환산(반올림한 정수 원). [krwPerUnit]은 1단위당 원화.
  int toKrw(int minor, double krwPerUnit) => (toMajor(minor) * krwPerUnit).round();

  /// 환율을 보여줄 단위 수량: 1, 100, 1000 중 "단위 × 1단위 환율 ≥ 10원"인 가장 작은 값.
  /// 예: USD → 1, JPY(약 8.47원) → 100, VND(약 0.052원) → 1000.
  int displayUnit(double krwPerUnit) {
    for (final unit in const [1, 100]) {
      if (unit * krwPerUnit >= 10) return unit;
    }
    return 1000;
  }

  /// "100엔", "1달러", "1,000동"
  String unitLabel(int unit) => '${NumberFormat('#,##0', 'en_US').format(unit)}$unitKo';
}

/// 원화 금액 표기: 10170 → "10,170원", -500 → "-500원"
String formatKrw(int won) => '${NumberFormat('#,##0', 'en_US').format(won)}원';

/// 환율 값 표기(소수 둘째 자리): 847.46 → "847.46원", 1339.2 → "1,339.20원"
String formatKrwRate(double won) => '${NumberFormat('#,##0.00', 'en_US').format(won)}원';

/// 우리 country 테이블에 있는 통화 17개. 소수 자릿수는 ISO 4217을 따르되, 실제로 소수 단위를
/// 쓰지 않는 엔·동·루피아는 0으로 둔다(지갑·환율 알림 설계 §5.4).
const _currencies = <String, CurrencyInfo>{
  'AUD': CurrencyInfo(code: 'AUD', minorDigits: 2, symbol: r'A$', nameKo: '호주 달러', unitKo: '호주달러'),
  'CAD': CurrencyInfo(code: 'CAD', minorDigits: 2, symbol: r'C$', nameKo: '캐나다 달러', unitKo: '캐나다달러'),
  'CHF': CurrencyInfo(code: 'CHF', minorDigits: 2, symbol: 'CHF ', nameKo: '스위스 프랑', unitKo: '프랑'),
  'CNY': CurrencyInfo(code: 'CNY', minorDigits: 2, symbol: 'CN¥', nameKo: '위안화', unitKo: '위안'),
  'CZK': CurrencyInfo(code: 'CZK', minorDigits: 2, symbol: 'Kč ', nameKo: '체코 코루나', unitKo: '코루나'),
  'EUR': CurrencyInfo(code: 'EUR', minorDigits: 2, symbol: '€', nameKo: '유로', unitKo: '유로'),
  'GBP': CurrencyInfo(code: 'GBP', minorDigits: 2, symbol: '£', nameKo: '영국 파운드', unitKo: '파운드'),
  'HKD': CurrencyInfo(code: 'HKD', minorDigits: 2, symbol: r'HK$', nameKo: '홍콩 달러', unitKo: '홍콩달러'),
  'IDR': CurrencyInfo(code: 'IDR', minorDigits: 0, symbol: 'Rp ', nameKo: '인도네시아 루피아', unitKo: '루피아'),
  'JPY': CurrencyInfo(code: 'JPY', minorDigits: 0, symbol: '¥', nameKo: '엔화', unitKo: '엔'),
  'PHP': CurrencyInfo(code: 'PHP', minorDigits: 2, symbol: '₱', nameKo: '필리핀 페소', unitKo: '페소'),
  'SGD': CurrencyInfo(code: 'SGD', minorDigits: 2, symbol: r'S$', nameKo: '싱가포르 달러', unitKo: '싱가포르달러'),
  'THB': CurrencyInfo(code: 'THB', minorDigits: 2, symbol: '฿', nameKo: '태국 바트', unitKo: '바트'),
  'TRY': CurrencyInfo(code: 'TRY', minorDigits: 2, symbol: '₺', nameKo: '튀르키예 리라', unitKo: '리라'),
  'TWD': CurrencyInfo(code: 'TWD', minorDigits: 2, symbol: r'NT$', nameKo: '대만 달러', unitKo: '대만달러'),
  'USD': CurrencyInfo(code: 'USD', minorDigits: 2, symbol: r'$', nameKo: '미국 달러', unitKo: '달러'),
  'VND': CurrencyInfo(code: 'VND', minorDigits: 0, symbol: '₫', nameKo: '베트남 동', unitKo: '동'),
};

/// 통화 코드로 표시 규칙을 찾는다. 표에 없는 통화는 코드를 기호로 쓰고 소수 2자리로 다룬다.
CurrencyInfo currencyInfoOf(String code) {
  final upper = code.trim().toUpperCase();
  return _currencies[upper] ??
      CurrencyInfo(code: upper, minorDigits: 2, symbol: '$upper ', nameKo: upper, unitKo: ' $upper');
}
```

- [ ] **Step 4: `expense_category.dart` 작성**

`app/lib/features/wallet/domain/expense_category.dart`:

```dart
/// 지출 카테고리 5종(지갑·환율 알림 설계 §5.3). DB에는 [code]를 문자열로 저장한다 —
/// enum 순서(index)로 저장하면 나중에 순서가 바뀔 때 기존 기록의 의미가 조용히 바뀐다.
enum ExpenseCategory {
  food('FOOD', '식비'),
  lodging('LODGING', '숙박'),
  transport('TRANSPORT', '교통'),
  sightseeing('SIGHTSEEING', '관광'),
  other('OTHER', '기타');

  const ExpenseCategory(this.code, this.labelKo);

  final String code;
  final String labelKo;

  /// 메모 입력란 힌트. 관광·기타는 무엇을 넣는 칸인지 예를 보여준다.
  String get memoHint {
    switch (this) {
      case ExpenseCategory.sightseeing:
        return '입장료, 투어 등';
      case ExpenseCategory.other:
        return '여행자보험, eSIM 등';
      default:
        return '메모 (선택)';
    }
  }

  /// 저장된 코드로 카테고리를 찾는다. 모르는 코드는 기타로 본다(기록을 숨기지 않기 위해).
  static ExpenseCategory fromCode(String code) =>
      values.firstWhere((c) => c.code == code, orElse: () => ExpenseCategory.other);
}
```

- [ ] **Step 5: `month_day.dart` 작성**

`app/lib/features/wallet/domain/month_day.dart`:

```dart
/// 지갑 화면의 날짜 표기: 2026-10-09 → "10월 9일". 여행 기간 안의 기록이라 연도는 생략한다.
String formatMonthDay(DateTime date) => '${date.month}월 ${date.day}일';
```

- [ ] **Step 6: 통과 확인**

Run: `flutter test test/wallet/currency_info_test.dart`
Expected: PASS (전부)

Run: `dart analyze lib/features/wallet test/wallet`
Expected: `No issues found!`

- [ ] **Step 7: 커밋**

```bash
git add lib/features/wallet/domain/currency_info.dart lib/features/wallet/domain/expense_category.dart \
  lib/features/wallet/domain/month_day.dart test/wallet/currency_info_test.dart
git commit -m "feat(app): 지갑용 통화 표시·금액 변환 규칙 추가"
```

---

### Task 2: 서버 환율 조회 + 기기 캐시

**Files:**
- Create: `app/lib/features/wallet/data/exchange_rate.dart`
- Create: `app/lib/features/wallet/data/exchange_rate_api.dart`
- Create: `app/lib/features/wallet/data/rate_cache.dart`
- Create: `app/lib/features/wallet/data/wallet_rate.dart`
- Test: `app/test/wallet/exchange_rate_test.dart`, `app/test/wallet/rate_cache_test.dart`, `app/test/wallet/wallet_rate_test.dart`

**Interfaces:**
- Consumes: `apiClientProvider`(`lib/core/network/api_client.dart`), `sharedPreferencesProvider`(`lib/core/prefs/shared_preferences_provider.dart`), 테스트 헬퍼 `StubHttpClientAdapter`(`test/support/stub_http_client_adapter.dart`, 생성자 `path`·`statusCode`·`body`, 필드 `lastRequest`)
- Produces:
  - `class ExchangeRate { String currencyCode; double krwRate; DateTime baseDate; double? previousKrwRate; DateTime? previousBaseDate; double? changePercent; String source; bool get isReference; factory fromJson(Map<String, dynamic>); Map<String, dynamic> toJson(); }`
  - `class RateSnapshot { ExchangeRate rate; DateTime fetchedAt; toJson(); factory fromJson(); }`
  - `class ExchangeRateApi { ExchangeRateApi(Dio); Future<ExchangeRate> getRate(String currencyCode); }`, `exchangeRateApiProvider`
  - `class RateCache { RateCache(SharedPreferences); static String keyOf(String code); RateSnapshot? read(String code); Future<void> write(String code, RateSnapshot snapshot); }`, `rateCacheProvider`
  - `Stream<RateSnapshot?> loadWalletRate({required RateCache cache, required ExchangeRateApi api, required DateTime Function() now, required String currencyCode})`
  - `walletRateProvider` — `StreamProvider.family<RateSnapshot?, String>` (인자: 통화 코드)

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/wallet/exchange_rate_test.dart`:

```dart
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/exchange_rate_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_http_client_adapter.dart';

void main() {
  test('수출입은행 환율 응답을 모두 읽는다', () {
    final rate = ExchangeRate.fromJson({
      'currencyCode': 'JPY',
      'krwRate': 8.4746,
      'baseDate': '2026-10-08',
      'previousKrwRate': 8.491,
      'previousBaseDate': '2026-10-07',
      'changePercent': -0.19,
      'source': 'EXIM',
    });

    expect(rate.currencyCode, 'JPY');
    expect(rate.krwRate, 8.4746);
    expect(rate.baseDate, DateTime(2026, 10, 8));
    expect(rate.previousKrwRate, 8.491);
    expect(rate.previousBaseDate, DateTime(2026, 10, 7));
    expect(rate.changePercent, -0.19);
    expect(rate.isReference, isFalse);
  });

  test('참고환율은 이전값이 없을 수 있다', () {
    final rate = ExchangeRate.fromJson({
      'currencyCode': 'VND',
      'krwRate': 0.051934,
      'baseDate': '2026-10-09',
      'previousKrwRate': null,
      'previousBaseDate': null,
      'changePercent': null,
      'source': 'ER_API',
    });

    expect(rate.previousKrwRate, isNull);
    expect(rate.changePercent, isNull);
    expect(rate.isReference, isTrue);
  });

  test('toJson으로 저장한 값을 fromJson으로 그대로 되읽는다', () {
    final original = ExchangeRate(
      currencyCode: 'USD',
      krwRate: 1339.2,
      baseDate: DateTime(2026, 10, 8),
      previousKrwRate: 1343.4,
      previousBaseDate: DateTime(2026, 10, 7),
      changePercent: -0.31,
      source: 'EXIM',
    );

    final restored = ExchangeRate.fromJson(original.toJson());

    expect(restored.krwRate, 1339.2);
    expect(restored.baseDate, DateTime(2026, 10, 8));
    expect(restored.previousBaseDate, DateTime(2026, 10, 7));
    expect(restored.changePercent, -0.31);
    expect(restored.source, 'EXIM');
  });

  test('getRate는 대문자 통화 코드 경로로 조회한다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/exchange-rates/JPY',
      statusCode: 200,
      body: '{"currencyCode":"JPY","krwRate":8.4746,"baseDate":"2026-10-08",'
          '"previousKrwRate":null,"previousBaseDate":null,"changePercent":null,"source":"EXIM"}',
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter;

    final rate = await ExchangeRateApi(dio).getRate('jpy');

    expect(adapter.lastRequest!.path, '/api/exchange-rates/JPY');
    expect(rate.krwRate, 8.4746);
  });
}
```

`app/test/wallet/rate_cache_test.dart`:

```dart
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/rate_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  RateSnapshot snapshot() => RateSnapshot(
        rate: ExchangeRate(
          currencyCode: 'JPY',
          krwRate: 8.4746,
          baseDate: DateTime(2026, 10, 8),
          changePercent: 0.42,
          source: 'EXIM',
        ),
        fetchedAt: DateTime(2026, 10, 9, 12, 30),
      );

  test('저장한 환율을 통화별 키로 되읽는다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = RateCache(prefs);

    await cache.write('jpy', snapshot());
    final read = cache.read('JPY');

    expect(RateCache.keyOf('jpy'), 'rateCache.JPY');
    expect(read!.rate.krwRate, 8.4746);
    expect(read.rate.changePercent, 0.42);
    expect(read.fetchedAt, DateTime(2026, 10, 9, 12, 30));
  });

  test('저장된 값이 없으면 null', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = RateCache(await SharedPreferences.getInstance());

    expect(cache.read('USD'), isNull);
  });

  test('깨진 값은 없는 것으로 본다', () async {
    SharedPreferences.setMockInitialValues({'rateCache.USD': '{not json'});
    final cache = RateCache(await SharedPreferences.getInstance());

    expect(cache.read('USD'), isNull);
  });
}
```

`app/test/wallet/wallet_rate_test.dart`:

```dart
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/exchange_rate_api.dart';
import 'package:app/features/wallet/data/rate_cache.dart';
import 'package:app/features/wallet/data/wallet_rate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi implements ExchangeRateApi {
  _FakeApi({this.rate, this.fail = false});

  final ExchangeRate? rate;
  final bool fail;

  @override
  Future<ExchangeRate> getRate(String currencyCode) async {
    if (fail) throw Exception('네트워크 오류');
    return rate!;
  }
}

ExchangeRate _rate(double krwRate) => ExchangeRate(
      currencyCode: 'JPY',
      krwRate: krwRate,
      baseDate: DateTime(2026, 10, 8),
      source: 'EXIM',
    );

void main() {
  final now = DateTime(2026, 10, 9, 15);

  Future<RateCache> emptyCache() async {
    SharedPreferences.setMockInitialValues({});
    return RateCache(await SharedPreferences.getInstance());
  }

  test('캐시가 없고 서버가 응답하면 새 값을 내보내고 캐시에 저장한다', () async {
    final cache = await emptyCache();

    final values = await loadWalletRate(
      cache: cache, api: _FakeApi(rate: _rate(8.4746)), now: () => now, currencyCode: 'JPY',
    ).toList();

    expect(values, hasLength(1));
    expect(values.single!.rate.krwRate, 8.4746);
    expect(values.single!.fetchedAt, now);
    expect(cache.read('JPY')!.rate.krwRate, 8.4746);
  });

  test('캐시가 있으면 캐시를 먼저 내보내고 서버 값을 이어서 내보낸다', () async {
    final cache = await emptyCache();
    await cache.write('JPY', RateSnapshot(rate: _rate(8.40), fetchedAt: DateTime(2026, 10, 8)));

    final values = await loadWalletRate(
      cache: cache, api: _FakeApi(rate: _rate(8.4746)), now: () => now, currencyCode: 'JPY',
    ).toList();

    expect(values.map((v) => v!.rate.krwRate).toList(), [8.40, 8.4746]);
  });

  test('서버가 실패하면 캐시만 남는다', () async {
    final cache = await emptyCache();
    await cache.write('JPY', RateSnapshot(rate: _rate(8.40), fetchedAt: DateTime(2026, 10, 8)));

    final values = await loadWalletRate(
      cache: cache, api: _FakeApi(fail: true), now: () => now, currencyCode: 'JPY',
    ).toList();

    expect(values.map((v) => v!.rate.krwRate).toList(), [8.40]);
  });

  test('캐시도 없고 서버도 실패하면 null 하나를 내보낸다', () async {
    final cache = await emptyCache();

    final values = await loadWalletRate(
      cache: cache, api: _FakeApi(fail: true), now: () => now, currencyCode: 'JPY',
    ).toList();

    expect(values, [null]);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/wallet/exchange_rate_test.dart test/wallet/rate_cache_test.dart test/wallet/wallet_rate_test.dart`
Expected: FAIL — 컴파일 에러(파일 없음)

- [ ] **Step 3: `exchange_rate.dart` 작성**

`app/lib/features/wallet/data/exchange_rate.dart`:

```dart
/// 서버 `GET /api/exchange-rates/{code}` 응답(지갑·환율 알림 설계 §4.5).
class ExchangeRate {
  const ExchangeRate({
    required this.currencyCode,
    required this.krwRate,
    required this.baseDate,
    this.previousKrwRate,
    this.previousBaseDate,
    this.changePercent,
    required this.source,
  });

  final String currencyCode;

  /// 통화 1단위당 원화(JPY는 1엔 기준).
  final double krwRate;

  /// 고시일(배치를 돌린 날이 아니다).
  final DateTime baseDate;
  final double? previousKrwRate;
  final DateTime? previousBaseDate;

  /// 전 영업일 대비 등락률(%). 이전값이 없으면 null.
  final double? changePercent;

  /// "EXIM"(한국수출입은행 고시환율) 또는 "ER_API"(open.er-api.com 참고환율).
  final String source;

  /// 참고환율이면 화면에 출처(Rates By Exchange Rate API)를 함께 표기해야 한다.
  bool get isReference => source == 'ER_API';

  factory ExchangeRate.fromJson(Map<String, dynamic> json) => ExchangeRate(
        currencyCode: json['currencyCode'] as String,
        krwRate: (json['krwRate'] as num).toDouble(),
        baseDate: DateTime.parse(json['baseDate'] as String),
        previousKrwRate: (json['previousKrwRate'] as num?)?.toDouble(),
        previousBaseDate: json['previousBaseDate'] == null
            ? null
            : DateTime.parse(json['previousBaseDate'] as String),
        changePercent: (json['changePercent'] as num?)?.toDouble(),
        source: json['source'] as String? ?? 'EXIM',
      );

  Map<String, dynamic> toJson() => {
        'currencyCode': currencyCode,
        'krwRate': krwRate,
        'baseDate': _isoDate(baseDate),
        'previousKrwRate': previousKrwRate,
        'previousBaseDate': previousBaseDate == null ? null : _isoDate(previousBaseDate!),
        'changePercent': changePercent,
        'source': source,
      };

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 화면이 쓰는 환율 한 벌 + 그 값을 받은 시각. 기기 캐시에도 이 모양 그대로 저장한다.
class RateSnapshot {
  const RateSnapshot({required this.rate, required this.fetchedAt});

  final ExchangeRate rate;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
        'rate': rate.toJson(),
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory RateSnapshot.fromJson(Map<String, dynamic> json) => RateSnapshot(
        rate: ExchangeRate.fromJson(json['rate'] as Map<String, dynamic>),
        fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      );
}
```

- [ ] **Step 4: `exchange_rate_api.dart` 작성**

`app/lib/features/wallet/data/exchange_rate_api.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'exchange_rate.dart';

/// 서버 환율 조회. 서버가 배치로 채운 캐시를 읽기만 하는 API라 로그인 토큰 없이도 동작한다
/// (3단계의 백그라운드 알림 작업이 그대로 쓴다).
class ExchangeRateApi {
  ExchangeRateApi(this._dio);

  final Dio _dio;

  Future<ExchangeRate> getRate(String currencyCode) async {
    final response = await _dio
        .get<Map<String, dynamic>>('/api/exchange-rates/${currencyCode.toUpperCase()}');
    return ExchangeRate.fromJson(response.data!);
  }
}

final exchangeRateApiProvider = Provider<ExchangeRateApi>((ref) {
  return ExchangeRateApi(ref.watch(apiClientProvider));
});
```

- [ ] **Step 5: `rate_cache.dart` 작성**

`app/lib/features/wallet/data/rate_cache.dart`:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import 'exchange_rate.dart';

/// 통화별 마지막 환율을 기기에 저장한다(설계 §5.5). 해외에서 데이터가 끊겨도
/// 지갑이 마지막 값과 고시일을 보여줄 수 있게 하기 위해서다.
class RateCache {
  RateCache(this._prefs);

  final SharedPreferences _prefs;

  static String keyOf(String currencyCode) => 'rateCache.${currencyCode.toUpperCase()}';

  RateSnapshot? read(String currencyCode) {
    final raw = _prefs.getString(keyOf(currencyCode));
    if (raw == null) return null;
    try {
      return RateSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null; // 깨진 캐시는 없는 것으로 보고, 다음 조회 때 덮어쓴다.
    } on TypeError {
      return null; // 예전 형식으로 저장된 값도 마찬가지다.
    }
  }

  Future<void> write(String currencyCode, RateSnapshot snapshot) =>
      _prefs.setString(keyOf(currencyCode), jsonEncode(snapshot.toJson()));
}

final rateCacheProvider = Provider<RateCache>((ref) {
  return RateCache(ref.watch(sharedPreferencesProvider));
});
```

- [ ] **Step 6: `wallet_rate.dart` 작성**

`app/lib/features/wallet/data/wallet_rate.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'exchange_rate.dart';
import 'exchange_rate_api.dart';
import 'rate_cache.dart';

/// 캐시를 먼저 내보내고(오프라인에서도 화면이 바로 그려지게) 서버에서 새 값을 받으면 한 번 더 내보낸다.
/// 서버가 실패하면 캐시만 남는다. 캐시도 없고 서버도 실패하면 null 하나(= "환율 정보 없음").
Stream<RateSnapshot?> loadWalletRate({
  required RateCache cache,
  required ExchangeRateApi api,
  required DateTime Function() now,
  required String currencyCode,
}) async* {
  final cached = cache.read(currencyCode);
  if (cached != null) yield cached;
  try {
    final fresh = RateSnapshot(rate: await api.getRate(currencyCode), fetchedAt: now());
    await cache.write(currencyCode, fresh);
    yield fresh;
  } catch (_) {
    // 네트워크·서버 오류는 화면을 막지 않는다: 캐시가 있으면 이미 내보냈다.
    if (cached == null) yield null;
  }
}

/// 통화 코드별 지갑 환율. 당겨서 새로고침은 이 프로바이더를 invalidate 한다.
final walletRateProvider =
    StreamProvider.family<RateSnapshot?, String>((ref, currencyCode) {
  return loadWalletRate(
    cache: ref.watch(rateCacheProvider),
    api: ref.watch(exchangeRateApiProvider),
    now: DateTime.now,
    currencyCode: currencyCode,
  );
});
```

- [ ] **Step 7: 통과 확인**

Run: `flutter test test/wallet/exchange_rate_test.dart test/wallet/rate_cache_test.dart test/wallet/wallet_rate_test.dart`
Expected: PASS (4 + 3 + 4)

Run: `dart analyze lib/features/wallet test/wallet`
Expected: `No issues found!`

- [ ] **Step 8: 커밋**

```bash
git add lib/features/wallet/data/exchange_rate.dart lib/features/wallet/data/exchange_rate_api.dart \
  lib/features/wallet/data/rate_cache.dart lib/features/wallet/data/wallet_rate.dart \
  test/wallet/exchange_rate_test.dart test/wallet/rate_cache_test.dart test/wallet/wallet_rate_test.dart
git commit -m "feat(app): 지갑 환율 조회와 기기 캐시 추가"
```

---

### Task 3: 지갑 로컬 DB + 합계·목록 규칙

**Files:**
- Create: `app/lib/features/wallet/data/wallet_database.dart` (+ 생성물 `wallet_database.g.dart`)
- Create: `app/lib/features/wallet/domain/wallet_summary.dart`
- Create: `app/lib/features/wallet/domain/wallet_entries.dart`
- Test: `app/test/wallet/wallet_fixtures.dart`, `app/test/wallet/wallet_database_test.dart`, `app/test/wallet/wallet_summary_test.dart`, `app/test/wallet/wallet_entries_test.dart`

**Interfaces:**
- Consumes: Task 1 `ExpenseCategory`, `CurrencyInfo`, `currencyInfoOf`; Task 2 `ExchangeRate`, `RateSnapshot`
- Produces:
  - drift 데이터 클래스 `ExpenseRow {int id; String isoAlpha2; String currencyCode; String category; int amountMinor; double? krwPerUnitAtEntry; String memo; DateTime spentOn; copyWith(...)}`, `ExchangeRow {int id; String isoAlpha2; String currencyCode; int amountMinor; int? krwPaid; String memo; DateTime exchangedOn; copyWith(...)}`
  - `class WalletDatabase { WalletDatabase(); WalletDatabase.forTesting(QueryExecutor); Future<int> addExpense({required String isoAlpha2, required String currencyCode, required String category, required int amountMinor, double? krwPerUnitAtEntry, String memo = '', required DateTime spentOn}); Future<void> updateExpense(ExpenseRow row); Future<void> deleteExpense(int id); Future<int> addExchange({required String isoAlpha2, required String currencyCode, required int amountMinor, int? krwPaid, String memo = '', required DateTime exchangedOn}); Future<void> updateExchange(ExchangeRow row); Future<void> deleteExchange(int id); Stream<List<ExpenseRow>> watchExpenses(String isoAlpha2); Stream<List<ExchangeRow>> watchExchanges(String isoAlpha2); Future<void> clearWallet(String isoAlpha2); }`
  - `walletDatabaseProvider` (`Provider<WalletDatabase>`), `walletExpensesProvider` (`StreamProvider.family<List<ExpenseRow>, String>`, 인자 isoAlpha2), `walletExchangesProvider` (`StreamProvider.family<List<ExchangeRow>, String>`)
  - `class WalletSummary { int exchangedMinor; int spentMinor; Map<ExpenseCategory, int> spentByCategory; int exchangedWithPaidMinor; int krwPaidTotal; int get balanceMinor; int? valuationGainKrw(CurrencyInfo currency, double? krwPerUnit); factory WalletSummary.of({required List<ExpenseRow> expenses, required List<ExchangeRow> exchanges}); }`
  - `sealed class WalletEntry { DateTime get date; int get id; }`, `ExpenseEntry(ExpenseRow row)`, `ExchangeEntry(ExchangeRow row)`, `List<WalletEntry> buildWalletEntries({required List<ExpenseRow> expenses, required List<ExchangeRow> exchanges, ExpenseCategory? filter})`, `List<(DateTime, List<WalletEntry>)> groupByDate(List<WalletEntry> entries)`
  - 테스트 픽스처(이후 태스크가 import): `expense(...)`, `exchange(...)`, `snapshot(...)` in `test/wallet/wallet_fixtures.dart`

- [ ] **Step 1: DB 정의 작성(코드 생성 전이라 아직 컴파일되지 않는다)**

`app/lib/features/wallet/data/wallet_database.dart`:

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'wallet_database.g.dart';

/// 지출 기록. 금액은 현지 통화 최소단위 정수(엔은 1엔, 달러는 1센트).
@DataClassName('ExpenseRow')
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get isoAlpha2 => text()();
  TextColumn get currencyCode => text()();

  /// `ExpenseCategory.code` (FOOD, LODGING, TRANSPORT, SIGHTSEEING, OTHER)
  TextColumn get category => text()();
  IntColumn get amountMinor => integer()();

  /// 기록한 순간의 1단위당 원화. 이미 쓴 돈의 원화 값은 이 값으로 고정한다(설계 §5.3).
  /// 그때 환율을 몰랐으면 null이고, 화면에 "환율 없음"으로 보인다.
  RealColumn get krwPerUnitAtEntry => real().nullable()();
  TextColumn get memo => text().withDefault(const Constant(''))();
  DateTimeColumn get spentOn => dateTime()();
}

/// 환전 기록. [amountMinor]는 받은 현지 통화, [krwPaid]는 그때 낸 원화(선택, 평가손익 계산용).
@DataClassName('ExchangeRow')
class Exchanges extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get isoAlpha2 => text()();
  TextColumn get currencyCode => text()();
  IntColumn get amountMinor => integer()();
  IntColumn get krwPaid => integer().nullable()();
  TextColumn get memo => text().withDefault(const Constant(''))();
  DateTimeColumn get exchangedOn => dateTime()();
}

/// 지갑 전용 로컬 DB(`wallet.sqlite`). 발걸음 기능의 AppDatabase와 파일을 나눠,
/// 서로의 스키마 마이그레이션이 영향을 주지 않게 한다(설계 §5.4). 서버에는 저장하지 않는다.
@DriftDatabase(tables: [Expenses, Exchanges])
class WalletDatabase extends _$WalletDatabase {
  WalletDatabase() : super(_openConnection());

  /// 테스트에서 인메모리 DB를 주입하기 위한 생성자.
  WalletDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  Future<int> addExpense({
    required String isoAlpha2,
    required String currencyCode,
    required String category,
    required int amountMinor,
    double? krwPerUnitAtEntry,
    String memo = '',
    required DateTime spentOn,
  }) {
    return into(expenses).insert(ExpensesCompanion.insert(
      isoAlpha2: isoAlpha2,
      currencyCode: currencyCode,
      category: category,
      amountMinor: amountMinor,
      krwPerUnitAtEntry: Value(krwPerUnitAtEntry),
      memo: Value(memo),
      spentOn: spentOn,
    ));
  }

  Future<void> updateExpense(ExpenseRow row) async {
    await update(expenses).replace(row);
  }

  Future<void> deleteExpense(int id) async {
    await (delete(expenses)..where((e) => e.id.equals(id))).go();
  }

  Future<int> addExchange({
    required String isoAlpha2,
    required String currencyCode,
    required int amountMinor,
    int? krwPaid,
    String memo = '',
    required DateTime exchangedOn,
  }) {
    return into(exchanges).insert(ExchangesCompanion.insert(
      isoAlpha2: isoAlpha2,
      currencyCode: currencyCode,
      amountMinor: amountMinor,
      krwPaid: Value(krwPaid),
      memo: Value(memo),
      exchangedOn: exchangedOn,
    ));
  }

  Future<void> updateExchange(ExchangeRow row) async {
    await update(exchanges).replace(row);
  }

  Future<void> deleteExchange(int id) async {
    await (delete(exchanges)..where((x) => x.id.equals(id))).go();
  }

  /// 한 나라의 지출. 최근 날짜 먼저, 같은 날은 나중에 넣은 것 먼저.
  Stream<List<ExpenseRow>> watchExpenses(String isoAlpha2) {
    return (select(expenses)
          ..where((e) => e.isoAlpha2.equals(isoAlpha2))
          ..orderBy([(e) => OrderingTerm.desc(e.spentOn), (e) => OrderingTerm.desc(e.id)]))
        .watch();
  }

  /// 한 나라의 환전. 정렬 규칙은 [watchExpenses]와 같다.
  Stream<List<ExchangeRow>> watchExchanges(String isoAlpha2) {
    return (select(exchanges)
          ..where((x) => x.isoAlpha2.equals(isoAlpha2))
          ..orderBy([(x) => OrderingTerm.desc(x.exchangedOn), (x) => OrderingTerm.desc(x.id)]))
        .watch();
  }

  /// 이 나라의 지갑 기록(지출·환전)을 모두 지운다. 다른 나라 기록은 그대로 둔다.
  Future<void> clearWallet(String isoAlpha2) {
    return transaction(() async {
      await (delete(expenses)..where((e) => e.isoAlpha2.equals(isoAlpha2))).go();
      await (delete(exchanges)..where((x) => x.isoAlpha2.equals(isoAlpha2))).go();
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    return NativeDatabase.createInBackground(File(p.join(dbFolder.path, 'wallet.sqlite')));
  });
}

final walletDatabaseProvider = Provider<WalletDatabase>((ref) {
  final db = WalletDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 나라(isoAlpha2)별 지출 목록. DB가 바뀌면 자동으로 다시 내보낸다.
final walletExpensesProvider =
    StreamProvider.family<List<ExpenseRow>, String>((ref, isoAlpha2) {
  return ref.watch(walletDatabaseProvider).watchExpenses(isoAlpha2);
});

/// 나라(isoAlpha2)별 환전 목록.
final walletExchangesProvider =
    StreamProvider.family<List<ExchangeRow>, String>((ref, isoAlpha2) {
  return ref.watch(walletDatabaseProvider).watchExchanges(isoAlpha2);
});
```

- [ ] **Step 2: drift 코드 생성**

Run: `dart run build_runner build --delete-conflicting-outputs --force-jit`
Expected: `Built with build_runner/jit ...`, `lib/features/wallet/data/wallet_database.g.dart` 생성

Run: `git checkout -- lib/core/db/app_database.g.dart`
(팀원 파일의 줄바꿈만 바뀐 재생성분을 되돌린다. `git status`에 `app_database.g.dart`가 남아 있으면 안 된다.)

- [ ] **Step 3: 실패하는 테스트 작성**

`app/test/wallet/wallet_fixtures.dart`:

```dart
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/wallet_database.dart';
import 'package:app/features/wallet/domain/expense_category.dart';

ExpenseRow expense({
  int id = 1,
  String iso = 'JP',
  String currency = 'JPY',
  ExpenseCategory category = ExpenseCategory.food,
  required int amount,
  double? krwAt,
  String memo = '',
  DateTime? on,
}) {
  return ExpenseRow(
    id: id,
    isoAlpha2: iso,
    currencyCode: currency,
    category: category.code,
    amountMinor: amount,
    krwPerUnitAtEntry: krwAt,
    memo: memo,
    spentOn: on ?? DateTime(2026, 10, 9),
  );
}

ExchangeRow exchange({
  int id = 1,
  String iso = 'JP',
  String currency = 'JPY',
  required int amount,
  int? krwPaid,
  String memo = '',
  DateTime? on,
}) {
  return ExchangeRow(
    id: id,
    isoAlpha2: iso,
    currencyCode: currency,
    amountMinor: amount,
    krwPaid: krwPaid,
    memo: memo,
    exchangedOn: on ?? DateTime(2026, 10, 9),
  );
}

RateSnapshot snapshot({
  String code = 'JPY',
  double rate = 8.4746,
  double? change = 0.42,
  String source = 'EXIM',
  DateTime? baseDate,
}) {
  return RateSnapshot(
    rate: ExchangeRate(
      currencyCode: code,
      krwRate: rate,
      baseDate: baseDate ?? DateTime(2026, 10, 8),
      changePercent: change,
      source: source,
    ),
    fetchedAt: DateTime(2026, 10, 9, 12),
  );
}
```

`app/test/wallet/wallet_database_test.dart`:

```dart
import 'package:app/features/wallet/data/wallet_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WalletDatabase db;

  setUp(() => db = WalletDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('지출을 저장하면 그 나라 목록에 그대로 나온다', () async {
    await db.addExpense(
      isoAlpha2: 'JP', currencyCode: 'JPY', category: 'FOOD', amountMinor: 1200,
      krwPerUnitAtEntry: 8.4746, memo: '라멘', spentOn: DateTime(2026, 10, 9),
    );

    final rows = await db.watchExpenses('JP').first;

    expect(rows, hasLength(1));
    expect(rows.single.amountMinor, 1200);
    expect(rows.single.category, 'FOOD');
    expect(rows.single.krwPerUnitAtEntry, 8.4746);
    expect(rows.single.memo, '라멘');
    expect(rows.single.spentOn, DateTime(2026, 10, 9));
  });

  test('나라별로 나뉘고, 최근 날짜·나중 기록이 먼저 온다', () async {
    await db.addExpense(isoAlpha2: 'JP', currencyCode: 'JPY', category: 'FOOD',
        amountMinor: 100, spentOn: DateTime(2026, 10, 8));
    await db.addExpense(isoAlpha2: 'JP', currencyCode: 'JPY', category: 'FOOD',
        amountMinor: 200, spentOn: DateTime(2026, 10, 9));
    await db.addExpense(isoAlpha2: 'JP', currencyCode: 'JPY', category: 'FOOD',
        amountMinor: 300, spentOn: DateTime(2026, 10, 9));
    await db.addExpense(isoAlpha2: 'VN', currencyCode: 'VND', category: 'FOOD',
        amountMinor: 50000, spentOn: DateTime(2026, 10, 9));

    final rows = await db.watchExpenses('JP').first;

    expect(rows.map((r) => r.amountMinor).toList(), [300, 200, 100]);
  });

  test('지출을 수정하고 삭제할 수 있다', () async {
    final id = await db.addExpense(isoAlpha2: 'JP', currencyCode: 'JPY', category: 'FOOD',
        amountMinor: 1200, spentOn: DateTime(2026, 10, 9));
    final row = (await db.watchExpenses('JP').first).single;

    await db.updateExpense(row.copyWith(amountMinor: 1500, category: 'TRANSPORT'));
    final updated = (await db.watchExpenses('JP').first).single;
    expect(updated.amountMinor, 1500);
    expect(updated.category, 'TRANSPORT');

    await db.deleteExpense(id);
    expect(await db.watchExpenses('JP').first, isEmpty);
  });

  test('환전을 저장·수정·삭제할 수 있다', () async {
    final id = await db.addExchange(isoAlpha2: 'JP', currencyCode: 'JPY', amountMinor: 50000,
        krwPaid: 420000, memo: '공항 환전', exchangedOn: DateTime(2026, 10, 9));
    final row = (await db.watchExchanges('JP').first).single;
    expect(row.krwPaid, 420000);

    await db.updateExchange(row.copyWith(amountMinor: 60000));
    expect((await db.watchExchanges('JP').first).single.amountMinor, 60000);

    await db.deleteExchange(id);
    expect(await db.watchExchanges('JP').first, isEmpty);
  });

  test('지갑 비우기는 그 나라의 지출·환전만 지운다', () async {
    await db.addExpense(isoAlpha2: 'JP', currencyCode: 'JPY', category: 'FOOD',
        amountMinor: 1200, spentOn: DateTime(2026, 10, 9));
    await db.addExchange(isoAlpha2: 'JP', currencyCode: 'JPY', amountMinor: 50000,
        exchangedOn: DateTime(2026, 10, 9));
    await db.addExpense(isoAlpha2: 'VN', currencyCode: 'VND', category: 'FOOD',
        amountMinor: 50000, spentOn: DateTime(2026, 10, 9));

    await db.clearWallet('JP');

    expect(await db.watchExpenses('JP').first, isEmpty);
    expect(await db.watchExchanges('JP').first, isEmpty);
    expect(await db.watchExpenses('VN').first, hasLength(1));
  });
}
```

`app/test/wallet/wallet_summary_test.dart`:

```dart
import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:app/features/wallet/domain/expense_category.dart';
import 'package:app/features/wallet/domain/wallet_summary.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_fixtures.dart';

void main() {
  final jpy = currencyInfoOf('JPY');

  test('환전·지출·잔액과 카테고리별 합계', () {
    final summary = WalletSummary.of(
      expenses: [
        expense(id: 1, amount: 1200),
        expense(id: 2, amount: 300),
        expense(id: 3, category: ExpenseCategory.lodging, amount: 16100),
      ],
      exchanges: [exchange(amount: 50000)],
    );

    expect(summary.exchangedMinor, 50000);
    expect(summary.spentMinor, 17600);
    expect(summary.balanceMinor, 32400);
    expect(summary.spentByCategory[ExpenseCategory.food], 1500);
    expect(summary.spentByCategory[ExpenseCategory.lodging], 16100);
    expect(summary.spentByCategory[ExpenseCategory.transport], 0);
  });

  test('평가손익은 낸 원화가 입력된 환전분만 현재 환율로 계산한다', () {
    final summary = WalletSummary.of(
      expenses: const [],
      exchanges: [
        exchange(id: 1, amount: 50000, krwPaid: 420000),
        exchange(id: 2, amount: 10000),
      ],
    );

    expect(summary.valuationGainKrw(jpy, 8.4746), 3730);
  });

  test('낸 원화 기록이 없거나 환율을 모르면 평가손익은 null', () {
    final noPaid = WalletSummary.of(expenses: const [], exchanges: [exchange(amount: 50000)]);
    final withPaid = WalletSummary.of(
        expenses: const [], exchanges: [exchange(amount: 50000, krwPaid: 420000)]);

    expect(noPaid.valuationGainKrw(jpy, 8.4746), isNull);
    expect(withPaid.valuationGainKrw(jpy, null), isNull);
  });
}
```

`app/test/wallet/wallet_entries_test.dart`:

```dart
import 'package:app/features/wallet/domain/expense_category.dart';
import 'package:app/features/wallet/domain/wallet_entries.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_fixtures.dart';

void main() {
  final d8 = DateTime(2026, 10, 8);
  final d9 = DateTime(2026, 10, 9);

  test('최근 날짜 먼저, 같은 날은 지출 다음 환전, 같은 종류는 나중 기록 먼저', () {
    final entries = buildWalletEntries(
      expenses: [expense(id: 1, amount: 100, on: d9), expense(id: 2, amount: 200, on: d9),
        expense(id: 3, amount: 300, on: d8)],
      exchanges: [exchange(id: 1, amount: 50000, on: d9)],
    );

    expect(entries.map(_describe).toList(), ['지출2', '지출1', '환전1', '지출3']);
  });

  test('카테고리 필터가 있으면 그 카테고리 지출만 남고 환전은 빠진다', () {
    final entries = buildWalletEntries(
      expenses: [expense(id: 1, amount: 100), expense(id: 2, category: ExpenseCategory.lodging, amount: 200)],
      exchanges: [exchange(id: 1, amount: 50000)],
      filter: ExpenseCategory.lodging,
    );

    expect(entries.map(_describe).toList(), ['지출2']);
  });

  test('날짜별로 묶는다', () {
    final entries = buildWalletEntries(
      expenses: [expense(id: 1, amount: 100, on: d9), expense(id: 2, amount: 200, on: d8)],
      exchanges: [exchange(id: 1, amount: 50000, on: d9)],
    );

    final groups = groupByDate(entries);

    expect(groups.map((g) => g.$1).toList(), [d9, d8]);
    expect(groups.first.$2, hasLength(2));
  });
}

String _describe(WalletEntry entry) => switch (entry) {
      ExpenseEntry(:final row) => '지출${row.id}',
      ExchangeEntry(:final row) => '환전${row.id}',
    };
```

- [ ] **Step 4: 실패 확인**

Run: `flutter test test/wallet/wallet_database_test.dart test/wallet/wallet_summary_test.dart test/wallet/wallet_entries_test.dart`
Expected: `wallet_database_test.dart`는 PASS(DB는 Step 1~2에서 이미 생성), 나머지 두 파일은 FAIL — 컴파일 에러(`wallet_summary.dart`, `wallet_entries.dart` 없음)

- [ ] **Step 5: `wallet_summary.dart` 작성**

`app/lib/features/wallet/domain/wallet_summary.dart`:

```dart
import '../data/wallet_database.dart';
import 'currency_info.dart';
import 'expense_category.dart';

/// 지갑 화면 상단의 숫자들(설계 §5.2-3·4). 금액은 모두 현지 통화 최소단위.
class WalletSummary {
  const WalletSummary._({
    required this.exchangedMinor,
    required this.spentMinor,
    required this.spentByCategory,
    required this.exchangedWithPaidMinor,
    required this.krwPaidTotal,
  });

  factory WalletSummary.of({
    required List<ExpenseRow> expenses,
    required List<ExchangeRow> exchanges,
  }) {
    final byCategory = {for (final c in ExpenseCategory.values) c: 0};
    var spent = 0;
    for (final e in expenses) {
      spent += e.amountMinor;
      final category = ExpenseCategory.fromCode(e.category);
      byCategory[category] = byCategory[category]! + e.amountMinor;
    }
    var exchanged = 0;
    var withPaid = 0;
    var paid = 0;
    for (final x in exchanges) {
      exchanged += x.amountMinor;
      if (x.krwPaid != null) {
        withPaid += x.amountMinor;
        paid += x.krwPaid!;
      }
    }
    return WalletSummary._(
      exchangedMinor: exchanged,
      spentMinor: spent,
      spentByCategory: byCategory,
      exchangedWithPaidMinor: withPaid,
      krwPaidTotal: paid,
    );
  }

  final int exchangedMinor;
  final int spentMinor;

  /// 다섯 카테고리가 모두 키로 들어 있다(쓴 적 없으면 0).
  final Map<ExpenseCategory, int> spentByCategory;

  /// 낸 원화가 입력된 환전들의 현지 금액 합과, 그때 낸 원화 합. 평가손익 계산용.
  final int exchangedWithPaidMinor;
  final int krwPaidTotal;

  /// 남은 돈 = 환전 합계 − 지출 합계. 쓴 돈이 더 많으면 음수.
  int get balanceMinor => exchangedMinor - spentMinor;

  /// 평가손익(원) = 낸 원화가 입력된 환전분을 현재 환율로 바꾼 값 − 낸 원화.
  /// 그런 환전이 없거나 환율을 모르면 null.
  int? valuationGainKrw(CurrencyInfo currency, double? krwPerUnit) {
    if (krwPerUnit == null || exchangedWithPaidMinor == 0) return null;
    return currency.toKrw(exchangedWithPaidMinor, krwPerUnit) - krwPaidTotal;
  }
}
```

- [ ] **Step 6: `wallet_entries.dart` 작성**

`app/lib/features/wallet/domain/wallet_entries.dart`:

```dart
import '../data/wallet_database.dart';
import 'expense_category.dart';

/// 지갑 목록의 한 줄. 지출과 환전을 한 목록에서 날짜순으로 섞어 보여주기 위한 공통 모양.
sealed class WalletEntry {
  const WalletEntry();

  DateTime get date;
  int get id;
}

final class ExpenseEntry extends WalletEntry {
  const ExpenseEntry(this.row);

  final ExpenseRow row;

  @override
  DateTime get date => row.spentOn;

  @override
  int get id => row.id;
}

final class ExchangeEntry extends WalletEntry {
  const ExchangeEntry(this.row);

  final ExchangeRow row;

  @override
  DateTime get date => row.exchangedOn;

  @override
  int get id => row.id;
}

/// 목록에 그릴 순서로 합친다: 최근 날짜 먼저, 같은 날은 지출 다음 환전, 같은 종류는 나중 기록 먼저.
/// [filter]가 있으면 그 카테고리의 지출만 남기고 환전은 뺀다.
List<WalletEntry> buildWalletEntries({
  required List<ExpenseRow> expenses,
  required List<ExchangeRow> exchanges,
  ExpenseCategory? filter,
}) {
  final entries = <WalletEntry>[
    for (final e in expenses)
      if (filter == null || ExpenseCategory.fromCode(e.category) == filter) ExpenseEntry(e),
    if (filter == null)
      for (final x in exchanges) ExchangeEntry(x),
  ];
  entries.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    final byType = _typeOrder(a).compareTo(_typeOrder(b));
    if (byType != 0) return byType;
    return b.id.compareTo(a.id);
  });
  return entries;
}

int _typeOrder(WalletEntry entry) => entry is ExpenseEntry ? 0 : 1;

/// 같은 날짜끼리 묶는다(날짜 머리글용). 입력 순서를 그대로 유지한다.
List<(DateTime, List<WalletEntry>)> groupByDate(List<WalletEntry> entries) {
  final groups = <(DateTime, List<WalletEntry>)>[];
  for (final entry in entries) {
    final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
    if (groups.isNotEmpty && groups.last.$1 == day) {
      groups.last.$2.add(entry);
    } else {
      groups.add((day, [entry]));
    }
  }
  return groups;
}
```

- [ ] **Step 7: 통과 확인**

Run: `flutter test test/wallet/`
Expected: PASS (Task 1·2 테스트 포함 전부)

Run: `dart analyze lib/features/wallet test/wallet`
Expected: `No issues found!`

Run: `git status --short`
Expected: `lib/core/db/app_database.g.dart`가 목록에 없다.

- [ ] **Step 8: 커밋**

```bash
git add lib/features/wallet/data/wallet_database.dart lib/features/wallet/data/wallet_database.g.dart \
  lib/features/wallet/domain/wallet_summary.dart lib/features/wallet/domain/wallet_entries.dart \
  test/wallet/wallet_fixtures.dart test/wallet/wallet_database_test.dart \
  test/wallet/wallet_summary_test.dart test/wallet/wallet_entries_test.dart
git commit -m "feat(app): 지갑 로컬 DB(지출·환전)와 합계·목록 규칙 추가"
```

---

### Task 4: 환율 배너 + 남은 돈 카드

**Files:**
- Create: `app/lib/features/wallet/widgets/rate_banner.dart`
- Create: `app/lib/features/wallet/widgets/balance_card.dart`
- Test: `app/test/wallet/rate_banner_test.dart`, `app/test/wallet/balance_card_test.dart`

**Interfaces:**
- Consumes: Task 1 `CurrencyInfo`, `currencyInfoOf`, `formatKrw`, `formatKrwRate`, `formatMonthDay`; Task 2 `RateSnapshot`, `ExchangeRate`; Task 3 `WalletSummary`, 픽스처 `expense`/`exchange`/`snapshot`; `AppColors`, `AppTextStyles`, `WireframeCard`
- Produces:
  - `RateBanner({required CurrencyInfo currency, required RateSnapshot? snapshot})` — 키: `rateBannerRate`(환율 문구 Text), `rateBannerChange`(등락 Text). 3단계 알림 화면이 그대로 쓴다.
  - `BalanceCard({required CurrencyInfo currency, required WalletSummary summary, double? krwPerUnit})` — 키: `balanceLocal`, `balanceKrw`, `balanceGain`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/wallet/rate_banner_test.dart`:

```dart
import 'package:app/core/theme/app_colors.dart';
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:app/features/wallet/widgets/rate_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_fixtures.dart';

Future<void> _pump(WidgetTester tester, String code, RateSnapshot? snap) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(body: RateBanner(currency: currencyInfoOf(code), snapshot: snap)),
  ));
}

void main() {
  testWidgets('수출입은행 환율은 표시 단위·등락·고시일을 보여준다', (tester) async {
    await _pump(tester, 'JPY', snapshot(rate: 8.4746, change: 0.42));

    expect(find.text('100엔 = 847.46원'), findsOneWidget);
    expect(find.text('▲ 0.42%'), findsOneWidget);
    expect(find.text('10월 8일 고시 · 한국수출입은행'), findsOneWidget);
    final change = tester.widget<Text>(find.byKey(const Key('rateBannerChange')));
    expect(change.style!.color, AppColors.warn);
  });

  testWidgets('하락은 파란색 ▼로 보인다', (tester) async {
    await _pump(tester, 'USD', snapshot(code: 'USD', rate: 1339.2, change: -0.31));

    expect(find.text('1달러 = 1,339.20원'), findsOneWidget);
    expect(find.text('▼ 0.31%'), findsOneWidget);
    final change = tester.widget<Text>(find.byKey(const Key('rateBannerChange')));
    expect(change.style!.color, AppColors.accent);
  });

  testWidgets('참고환율은 출처를 표기하고, 이전값이 없으면 등락을 생략한다', (tester) async {
    await _pump(tester, 'VND', snapshot(code: 'VND', rate: 0.051934, change: null,
        source: 'ER_API', baseDate: DateTime(2026, 10, 9)));

    expect(find.text('1,000동 = 51.93원'), findsOneWidget);
    expect(find.text('10월 9일 기준 · 참고환율 · Rates By Exchange Rate API'), findsOneWidget);
    expect(find.byKey(const Key('rateBannerChange')), findsNothing);
  });

  testWidgets('환율이 없으면 안내 문구를 보여준다', (tester) async {
    await _pump(tester, 'JPY', null);

    expect(find.text('환율 정보 없음 · 아래로 당겨 다시 시도'), findsOneWidget);
  });
}
```

`app/test/wallet/balance_card_test.dart`:

```dart
import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:app/features/wallet/domain/expense_category.dart';
import 'package:app/features/wallet/domain/wallet_summary.dart';
import 'package:app/features/wallet/widgets/balance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_fixtures.dart';

Future<void> _pump(WidgetTester tester, WalletSummary summary, double? rate) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: BalanceCard(currency: currencyInfoOf('JPY'), summary: summary, krwPerUnit: rate),
    ),
  ));
}

void main() {
  final summary = WalletSummary.of(
    expenses: [expense(id: 1, amount: 1200), expense(id: 2, category: ExpenseCategory.lodging, amount: 16400)],
    exchanges: [exchange(amount: 50000)],
  );

  testWidgets('남은 돈과 현재 환율 원화 환산, 환전·지출 합계를 보여준다', (tester) async {
    await _pump(tester, summary, 8.4746);

    expect(find.text('남은 돈'), findsOneWidget);
    expect(find.text('¥32,400'), findsOneWidget);
    expect(find.text('≈ 274,577원'), findsOneWidget);
    expect(find.text('환전 ¥50,000 · 지출 ¥17,600'), findsOneWidget);
    expect(find.byKey(const Key('balanceGain')), findsNothing);
  });

  testWidgets('낸 원화가 입력된 환전이 있으면 평가손익을 보여준다', (tester) async {
    final paid = WalletSummary.of(
        expenses: const [], exchanges: [exchange(amount: 50000, krwPaid: 420000)]);

    await _pump(tester, paid, 8.4746);

    expect(find.text('환전 평가손익 +3,730원'), findsOneWidget);
  });

  testWidgets('환율을 모르면 원화 환산을 생략한다', (tester) async {
    await _pump(tester, summary, null);

    expect(find.byKey(const Key('balanceKrw')), findsNothing);
    expect(find.text('¥32,400'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/wallet/rate_banner_test.dart test/wallet/balance_card_test.dart`
Expected: FAIL — 컴파일 에러(위젯 파일 없음)

- [ ] **Step 3: `rate_banner.dart` 작성**

`app/lib/features/wallet/widgets/rate_banner.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../data/exchange_rate.dart';
import '../domain/currency_info.dart';
import '../domain/month_day.dart';

/// 지갑 상단의 환율 배너(설계 §5.2-2). 3단계 환율 알림 화면도 이 위젯을 그대로 쓴다.
class RateBanner extends StatelessWidget {
  const RateBanner({super.key, required this.currency, required this.snapshot});

  final CurrencyInfo currency;
  final RateSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final rate = snapshot?.rate;
    return WireframeCard(
      color: AppColors.infoBg,
      borderColor: AppColors.infoBorder,
      child: rate == null
          ? Text('환율 정보 없음 · 아래로 당겨 다시 시도', style: AppTextStyles.caption)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _rateText(rate),
                        key: const Key('rateBannerRate'),
                        style: AppTextStyles.cardTitle,
                      ),
                    ),
                    if (rate.changePercent != null) _ChangeLabel(percent: rate.changePercent!),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_sourceText(rate), style: AppTextStyles.caption),
              ],
            ),
    );
  }

  String _rateText(ExchangeRate rate) {
    final unit = currency.displayUnit(rate.krwRate);
    return '${currency.unitLabel(unit)} = ${formatKrwRate(unit * rate.krwRate)}';
  }

  /// 수출입은행 값은 "고시", 참고환율은 갱신일 "기준"과 이용 조건상 필수인 출처를 붙인다.
  String _sourceText(ExchangeRate rate) {
    final date = formatMonthDay(rate.baseDate);
    return rate.isReference
        ? '$date 기준 · 참고환율 · Rates By Exchange Rate API'
        : '$date 고시 · 한국수출입은행';
  }
}

/// 전 영업일 대비 등락. 상승은 주황(warn), 하락은 파랑(accent).
class _ChangeLabel extends StatelessWidget {
  const _ChangeLabel({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String arrow;
    if (percent > 0) {
      color = AppColors.warn;
      arrow = '▲';
    } else if (percent < 0) {
      color = AppColors.accent;
      arrow = '▼';
    } else {
      color = AppColors.textSecondary;
      arrow = '-';
    }
    return Text(
      '$arrow ${percent.abs().toStringAsFixed(2)}%',
      key: const Key('rateBannerChange'),
      style: AppTextStyles.chip.copyWith(color: color, fontWeight: FontWeight.w700),
    );
  }
}
```

- [ ] **Step 4: `balance_card.dart` 작성**

`app/lib/features/wallet/widgets/balance_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../domain/currency_info.dart';
import '../domain/wallet_summary.dart';

/// 남은 돈 카드(설계 §5.2-3). 원화 환산은 현재 환율로 계속 바뀐다.
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.currency,
    required this.summary,
    this.krwPerUnit,
  });

  final CurrencyInfo currency;
  final WalletSummary summary;

  /// 현재 1단위당 원화. 모르면 원화 환산과 평가손익을 생략한다.
  final double? krwPerUnit;

  @override
  Widget build(BuildContext context) {
    final rate = krwPerUnit;
    final gain = summary.valuationGainKrw(currency, rate);
    return WireframeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('남은 돈', style: AppTextStyles.label),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currency.format(summary.balanceMinor),
                key: const Key('balanceLocal'),
                style: AppTextStyles.screenTitle,
              ),
              if (rate != null) ...[
                const SizedBox(width: 8),
                Text(
                  '≈ ${formatKrw(currency.toKrw(summary.balanceMinor, rate))}',
                  key: const Key('balanceKrw'),
                  style: AppTextStyles.chip,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '환전 ${currency.format(summary.exchangedMinor)} · 지출 ${currency.format(summary.spentMinor)}',
            style: AppTextStyles.caption,
          ),
          if (gain != null) ...[
            const SizedBox(height: 4),
            Text(
              '환전 평가손익 ${gain >= 0 ? '+' : ''}${formatKrw(gain)}',
              key: const Key('balanceGain'),
              style: AppTextStyles.caption.copyWith(
                color: gain >= 0 ? AppColors.warn : AppColors.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: 통과 확인**

Run: `flutter test test/wallet/rate_banner_test.dart test/wallet/balance_card_test.dart`
Expected: PASS (4 + 3)

Run: `dart analyze lib/features/wallet test/wallet`
Expected: `No issues found!`

- [ ] **Step 6: 커밋**

```bash
git add lib/features/wallet/widgets/rate_banner.dart lib/features/wallet/widgets/balance_card.dart \
  test/wallet/rate_banner_test.dart test/wallet/balance_card_test.dart
git commit -m "feat(app): 지갑 환율 배너와 남은 돈 카드 추가"
```

---

### Task 5: 지출·환전 기록 바텀시트

**Files:**
- Create: `app/lib/features/wallet/widgets/form_date_row.dart`
- Create: `app/lib/features/wallet/widgets/expense_form_sheet.dart`
- Create: `app/lib/features/wallet/widgets/exchange_form_sheet.dart`
- Test: `app/test/wallet/expense_form_sheet_test.dart`, `app/test/wallet/exchange_form_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 `CurrencyInfo`, `currencyInfoOf`, `ExpenseCategory`, `formatMonthDay`; Task 3 `ExpenseRow`, `ExchangeRow`, 픽스처; `AppColors`, `AppTextStyles`, `PillButton`, `FilterPill`, `SectionLabel`
- Produces:
  - `FormDateRow({required DateTime date, required VoidCallback onTap})` — 키 `dateRow`
  - `class ExpenseInput { ExpenseCategory category; int amountMinor; String memo; DateTime spentOn; }`
  - `Future<ExpenseInput?> showExpenseFormSheet(BuildContext context, {required CurrencyInfo currency, ExpenseRow? initial, DateTime Function() today = DateTime.now})` — 키: `category_<CODE>`, `amountField`, `memoField`, `saveButton`
  - `class ExchangeInput { int amountMinor; int? krwPaid; String memo; DateTime exchangedOn; }`
  - `Future<ExchangeInput?> showExchangeFormSheet(BuildContext context, {required CurrencyInfo currency, ExchangeRow? initial, DateTime Function() today = DateTime.now})` — 키: `exchangeAmountField`, `krwPaidField`, `exchangeMemoField`, `saveButton`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/wallet/expense_form_sheet_test.dart`:

```dart
import 'package:app/features/wallet/data/wallet_database.dart';
import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:app/features/wallet/domain/expense_category.dart';
import 'package:app/features/wallet/widgets/expense_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_fixtures.dart';

/// 버튼을 눌러 시트를 열고, 시트가 돌려준 값을 [results]에 담는다.
Future<List<ExpenseInput?>> _pumpOpener(WidgetTester tester,
    {String code = 'JPY', ExpenseRow? initial}) async {
  final results = <ExpenseInput?>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(await showExpenseFormSheet(
            context,
            currency: currencyInfoOf(code),
            initial: initial,
            today: () => DateTime(2026, 10, 9, 18, 30),
          )),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('금액이 비어 있으면 오류를 보이고 닫히지 않는다', (tester) async {
    final results = await _pumpOpener(tester);

    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    expect(find.text('금액을 확인해 주세요'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('카테고리·금액·메모를 입력하면 그 값을 돌려준다(날짜는 오늘, 시각 제거)', (tester) async {
    final results = await _pumpOpener(tester);

    await tester.tap(find.byKey(const Key('category_SIGHTSEEING')));
    await tester.enterText(find.byKey(const Key('amountField')), '1,200');
    await tester.enterText(find.byKey(const Key('memoField')), '스카이트리');
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    final input = results.single!;
    expect(input.category, ExpenseCategory.sightseeing);
    expect(input.amountMinor, 1200);
    expect(input.memo, '스카이트리');
    expect(input.spentOn, DateTime(2026, 10, 9));
  });

  testWidgets('통화보다 소수 자릿수가 많으면 오류', (tester) async {
    await _pumpOpener(tester, code: 'USD');

    await tester.enterText(find.byKey(const Key('amountField')), '12.345');
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    expect(find.text('금액을 확인해 주세요'), findsOneWidget);
  });

  testWidgets('기타를 고르면 메모 힌트가 여행자보험·eSIM으로 바뀐다', (tester) async {
    await _pumpOpener(tester);

    await tester.tap(find.byKey(const Key('category_OTHER')));
    await tester.pump();

    final memo = tester.widget<TextField>(find.byKey(const Key('memoField')));
    expect(memo.decoration!.hintText, '여행자보험, eSIM 등');
  });

  testWidgets('수정 모드는 제목과 기존 값을 채운다', (tester) async {
    await _pumpOpener(tester,
        initial: expense(category: ExpenseCategory.lodging, amount: 16400, memo: '호텔'));

    expect(find.text('지출 수정'), findsOneWidget);
    expect(find.widgetWithText(TextField, '16400'), findsOneWidget);
    expect(find.widgetWithText(TextField, '호텔'), findsOneWidget);
  });
}
```

`app/test/wallet/exchange_form_sheet_test.dart`:

```dart
import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:app/features/wallet/widgets/exchange_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<ExchangeInput?>> _pumpOpener(WidgetTester tester) async {
  final results = <ExchangeInput?>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(await showExchangeFormSheet(
            context,
            currency: currencyInfoOf('JPY'),
            today: () => DateTime(2026, 10, 9),
          )),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('받은 금액과 낸 원화를 돌려준다', (tester) async {
    final results = await _pumpOpener(tester);

    await tester.enterText(find.byKey(const Key('exchangeAmountField')), '50,000');
    await tester.enterText(find.byKey(const Key('krwPaidField')), '420,000');
    await tester.enterText(find.byKey(const Key('exchangeMemoField')), '공항 환전');
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    final input = results.single!;
    expect(input.amountMinor, 50000);
    expect(input.krwPaid, 420000);
    expect(input.memo, '공항 환전');
    expect(input.exchangedOn, DateTime(2026, 10, 9));
  });

  testWidgets('낸 원화를 비우면 null', (tester) async {
    final results = await _pumpOpener(tester);

    await tester.enterText(find.byKey(const Key('exchangeAmountField')), '50000');
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    expect(results.single!.krwPaid, isNull);
  });

  testWidgets('낸 원화가 숫자가 아니면 오류', (tester) async {
    final results = await _pumpOpener(tester);

    await tester.enterText(find.byKey(const Key('exchangeAmountField')), '50000');
    await tester.enterText(find.byKey(const Key('krwPaidField')), 'abc');
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    expect(find.text('원화 금액을 확인해 주세요'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('받은 금액이 없으면 오류', (tester) async {
    final results = await _pumpOpener(tester);

    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    expect(find.text('금액을 확인해 주세요'), findsOneWidget);
    expect(results, isEmpty);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/wallet/expense_form_sheet_test.dart test/wallet/exchange_form_sheet_test.dart`
Expected: FAIL — 컴파일 에러(위젯 파일 없음)

- [ ] **Step 3: `form_date_row.dart` 작성**

`app/lib/features/wallet/widgets/form_date_row.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/month_day.dart';

/// 기록 폼의 날짜 행. 누르면 날짜 선택기를 연다(선택기는 부모가 띄운다).
class FormDateRow extends StatelessWidget {
  const FormDateRow({super.key, required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('dateRow'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('날짜', style: AppTextStyles.label),
            Text(
              '${formatMonthDay(date)} · 변경',
              style: AppTextStyles.chip.copyWith(color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// 시각을 떼고 날짜만 남긴다(지갑 기록은 날짜 단위).
DateTime dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
```

- [ ] **Step 4: `expense_form_sheet.dart` 작성**

`app/lib/features/wallet/widgets/expense_form_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../data/wallet_database.dart';
import '../domain/currency_info.dart';
import '../domain/expense_category.dart';
import 'form_date_row.dart';

/// 지출 폼의 결과값. 금액은 현지 통화 최소단위.
class ExpenseInput {
  const ExpenseInput({
    required this.category,
    required this.amountMinor,
    required this.memo,
    required this.spentOn,
  });

  final ExpenseCategory category;
  final int amountMinor;
  final String memo;
  final DateTime spentOn;
}

/// 지출 기록 바텀시트를 띄운다. [initial]이 있으면 수정 모드. 저장하면 값을, 닫으면 null을 돌려준다.
Future<ExpenseInput?> showExpenseFormSheet(
  BuildContext context, {
  required CurrencyInfo currency,
  ExpenseRow? initial,
  DateTime Function() today = DateTime.now,
}) {
  return showModalBottomSheet<ExpenseInput>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) => _ExpenseFormSheet(currency: currency, initial: initial, today: today),
  );
}

class _ExpenseFormSheet extends StatefulWidget {
  const _ExpenseFormSheet({required this.currency, this.initial, required this.today});

  final CurrencyInfo currency;
  final ExpenseRow? initial;
  final DateTime Function() today;

  @override
  State<_ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends State<_ExpenseFormSheet> {
  late ExpenseCategory _category;
  late final TextEditingController _amount;
  late final TextEditingController _memo;
  late DateTime _date;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _category = initial == null ? ExpenseCategory.food : ExpenseCategory.fromCode(initial.category);
    _amount = TextEditingController(
        text: initial == null ? '' : widget.currency.toInputText(initial.amountMinor));
    _memo = TextEditingController(text: initial?.memo ?? '');
    _date = dateOnly(initial?.spentOn ?? widget.today());
  }

  @override
  void dispose() {
    _amount.dispose();
    _memo.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  void _save() {
    final minor = widget.currency.parseToMinor(_amount.text);
    if (minor == null) {
      setState(() => _error = '금액을 확인해 주세요');
      return;
    }
    Navigator.of(context).pop(ExpenseInput(
      category: _category,
      amountMinor: minor,
      memo: _memo.text.trim(),
      spentOn: _date,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.initial == null ? '지출 기록' : '지출 수정', style: AppTextStyles.screenTitle),
              const SizedBox(height: 16),
              const SectionLabel('카테고리'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in ExpenseCategory.values)
                    FilterPill(
                      key: Key('category_${c.code}'),
                      label: c.labelKo,
                      selected: c == _category,
                      onTap: () => setState(() => _category = c),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('amountField'),
                controller: _amount,
                keyboardType: TextInputType.numberWithOptions(decimal: widget.currency.minorDigits > 0),
                decoration: InputDecoration(
                  labelText: '금액',
                  suffixText: widget.currency.code,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('memoField'),
                controller: _memo,
                decoration: InputDecoration(labelText: '메모', hintText: _category.memoHint),
              ),
              const SizedBox(height: 8),
              FormDateRow(date: _date, onTap: _pickDate),
              const SizedBox(height: 16),
              PillButton(key: const Key('saveButton'), label: '저장', onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: `exchange_form_sheet.dart` 작성**

`app/lib/features/wallet/widgets/exchange_form_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../data/wallet_database.dart';
import '../domain/currency_info.dart';
import 'form_date_row.dart';

/// 환전 폼의 결과값. [amountMinor]는 받은 현지 통화 최소단위, [krwPaid]는 낸 원화(선택).
class ExchangeInput {
  const ExchangeInput({
    required this.amountMinor,
    required this.krwPaid,
    required this.memo,
    required this.exchangedOn,
  });

  final int amountMinor;
  final int? krwPaid;
  final String memo;
  final DateTime exchangedOn;
}

/// 환전 기록 바텀시트를 띄운다. [initial]이 있으면 수정 모드.
Future<ExchangeInput?> showExchangeFormSheet(
  BuildContext context, {
  required CurrencyInfo currency,
  ExchangeRow? initial,
  DateTime Function() today = DateTime.now,
}) {
  return showModalBottomSheet<ExchangeInput>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) => _ExchangeFormSheet(currency: currency, initial: initial, today: today),
  );
}

class _ExchangeFormSheet extends StatefulWidget {
  const _ExchangeFormSheet({required this.currency, this.initial, required this.today});

  final CurrencyInfo currency;
  final ExchangeRow? initial;
  final DateTime Function() today;

  @override
  State<_ExchangeFormSheet> createState() => _ExchangeFormSheetState();
}

class _ExchangeFormSheetState extends State<_ExchangeFormSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _krwPaid;
  late final TextEditingController _memo;
  late DateTime _date;
  String? _amountError;
  String? _krwError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _amount = TextEditingController(
        text: initial == null ? '' : widget.currency.toInputText(initial.amountMinor));
    _krwPaid = TextEditingController(text: initial?.krwPaid?.toString() ?? '');
    _memo = TextEditingController(text: initial?.memo ?? '');
    _date = dateOnly(initial?.exchangedOn ?? widget.today());
  }

  @override
  void dispose() {
    _amount.dispose();
    _krwPaid.dispose();
    _memo.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  void _save() {
    final minor = widget.currency.parseToMinor(_amount.text);
    final krwText = _krwPaid.text.replaceAll(',', '').trim();
    final krw = krwText.isEmpty ? null : int.tryParse(krwText);
    final krwInvalid = krwText.isNotEmpty && (krw == null || krw <= 0);
    setState(() {
      _amountError = minor == null ? '금액을 확인해 주세요' : null;
      _krwError = krwInvalid ? '원화 금액을 확인해 주세요' : null;
    });
    if (minor == null || krwInvalid) return;
    Navigator.of(context).pop(ExchangeInput(
      amountMinor: minor,
      krwPaid: krw,
      memo: _memo.text.trim(),
      exchangedOn: _date,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.initial == null ? '환전 기록' : '환전 수정', style: AppTextStyles.screenTitle),
              const SizedBox(height: 16),
              TextField(
                key: const Key('exchangeAmountField'),
                controller: _amount,
                keyboardType: TextInputType.numberWithOptions(decimal: widget.currency.minorDigits > 0),
                decoration: InputDecoration(
                  labelText: '받은 금액',
                  suffixText: widget.currency.code,
                  errorText: _amountError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('krwPaidField'),
                controller: _krwPaid,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '낸 원화 (선택)',
                  suffixText: '원',
                  errorText: _krwError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('exchangeMemoField'),
                controller: _memo,
                decoration: const InputDecoration(labelText: '메모', hintText: '공항 환전, 현지 ATM 등'),
              ),
              const SizedBox(height: 8),
              FormDateRow(date: _date, onTap: _pickDate),
              const SizedBox(height: 16),
              PillButton(key: const Key('saveButton'), label: '저장', onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: 통과 확인**

Run: `flutter test test/wallet/expense_form_sheet_test.dart test/wallet/exchange_form_sheet_test.dart`
Expected: PASS (5 + 4)

Run: `dart analyze lib/features/wallet test/wallet`
Expected: `No issues found!`

- [ ] **Step 7: 커밋**

```bash
git add lib/features/wallet/widgets/form_date_row.dart lib/features/wallet/widgets/expense_form_sheet.dart \
  lib/features/wallet/widgets/exchange_form_sheet.dart \
  test/wallet/expense_form_sheet_test.dart test/wallet/exchange_form_sheet_test.dart
git commit -m "feat(app): 지출·환전 기록 바텀시트 폼 추가"
```

---

### Task 6: 지갑 화면 + 라우트

**Files:**
- Create: `app/lib/features/wallet/widgets/wallet_entry_list.dart`
- Create: `app/lib/features/wallet/wallet_page.dart`
- Modify: `app/lib/router.dart`
- Test: `app/test/wallet/wallet_page_test.dart`

**Interfaces:**
- Consumes: Task 1~5 전부; `countryDetailProvider`(`lib/core/network/country_detail_api.dart`, `FutureProvider.family<CountryDetail, String>`), `CountryDetail(isoAlpha2, nameKo, currencyCode, cardAcceptance, …)`
- Produces:
  - `WalletEntryList({required List<WalletEntry> entries, required CurrencyInfo currency, double? currentKrwPerUnit, required ValueChanged<ExpenseRow> onTapExpense, required ValueChanged<ExchangeRow> onTapExchange, required ValueChanged<ExpenseRow> onLongPressExpense, required ValueChanged<ExchangeRow> onLongPressExchange})` — 행 키 `entry_expense_<id>`, `entry_exchange_<id>`
  - `WalletPage({required String isoAlpha2})` — 키: `addExpenseButton`, `addExchangeButton`, `filter_ALL`, `filter_<CODE>`, `walletMenu`
  - `AppRoutes.wallet` = `'/checklist/wallet'`, `static String AppRoutes.walletOf(String isoAlpha2)` → `'/checklist/wallet?iso=JP'`

- [ ] **Step 1: 실패하는 화면 테스트 작성**

`app/test/wallet/wallet_page_test.dart`:

```dart
import 'package:app/core/network/country_detail_api.dart';
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/wallet_database.dart';
import 'package:app/features/wallet/data/wallet_rate.dart';
import 'package:app/features/wallet/domain/expense_category.dart';
import 'package:app/features/wallet/wallet_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_fixtures.dart';

Future<void> _pumpWallet(
  WidgetTester tester, {
  RateSnapshot? rate,
  List<ExpenseRow> expenses = const [],
  List<ExchangeRow> exchanges = const [],
  String? currencyCode = 'JPY',
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      countryDetailProvider.overrideWith((ref, iso) async => CountryDetail(
            isoAlpha2: 'JP',
            nameKo: '일본',
            currencyCode: currencyCode,
            cardAcceptance: 'MEDIUM',
          )),
      walletRateProvider.overrideWith((ref, code) => Stream<RateSnapshot?>.value(rate)),
      walletExpensesProvider.overrideWith((ref, iso) => Stream.value(expenses)),
      walletExchangesProvider.overrideWith((ref, iso) => Stream.value(exchanges)),
    ],
    child: const MaterialApp(home: Scaffold(body: WalletPage(isoAlpha2: 'JP'))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final sample = (
    expenses: [
      expense(id: 1, amount: 1200, krwAt: 8.4746, memo: '라멘'),
      expense(id: 2, category: ExpenseCategory.lodging, amount: 16400, krwAt: 8.4746, memo: '호텔'),
    ],
    exchanges: [exchange(id: 1, amount: 50000, memo: '공항 환전')],
  );

  testWidgets('헤더·배너·남은 돈·기록 목록을 보여준다', (tester) async {
    await _pumpWallet(tester,
        rate: snapshot(), expenses: sample.expenses, exchanges: sample.exchanges);

    expect(find.text('일본 지갑'), findsOneWidget);
    expect(find.text('100엔 = 847.46원'), findsOneWidget);
    expect(find.text('¥32,400'), findsOneWidget);
    expect(find.text('환전 ¥50,000 · 지출 ¥17,600'), findsOneWidget);
    expect(find.text('라멘'), findsOneWidget);
    expect(find.text('≈ 10,170원'), findsOneWidget);
    expect(find.text('+¥50,000'), findsOneWidget);
    expect(find.text('≈ 423,730원'), findsOneWidget);
    expect(find.text('10월 9일'), findsOneWidget);
  });

  testWidgets('카테고리를 고르면 그 지출만 남고 환전은 빠진다', (tester) async {
    await _pumpWallet(tester,
        rate: snapshot(), expenses: sample.expenses, exchanges: sample.exchanges);

    await tester.tap(find.byKey(const Key('filter_LODGING')));
    await tester.pumpAndSettle();

    expect(find.text('호텔'), findsOneWidget);
    expect(find.text('라멘'), findsNothing);
    expect(find.text('+¥50,000'), findsNothing);
  });

  testWidgets('기록이 없으면 안내를 보여준다', (tester) async {
    await _pumpWallet(tester, rate: snapshot());

    expect(find.text('아직 기록이 없습니다. 아래 버튼으로 지출이나 환전을 기록해 보세요.'), findsOneWidget);
  });

  testWidgets('환율을 모르면 배너 안내와 기록의 "환율 없음"을 보여준다', (tester) async {
    await _pumpWallet(tester, expenses: [expense(id: 1, amount: 1200, memo: '라멘')]);

    expect(find.text('환율 정보 없음 · 아래로 당겨 다시 시도'), findsOneWidget);
    expect(find.text('환율 없음'), findsOneWidget);
  });

  testWidgets('나라에 통화 정보가 없으면 지갑을 쓸 수 없다고 안내한다', (tester) async {
    await _pumpWallet(tester, currencyCode: null);

    expect(find.text('이 나라의 통화 정보가 없어 지갑을 쓸 수 없습니다.'), findsOneWidget);
    expect(find.byKey(const Key('addExpenseButton')), findsNothing);
  });

  testWidgets('지출 기록 버튼은 지출 폼을, 환전 기록 버튼은 환전 폼을 연다', (tester) async {
    await _pumpWallet(tester, rate: snapshot());

    await tester.tap(find.byKey(const Key('addExpenseButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('amountField')), findsOneWidget);

    Navigator.of(tester.element(find.byKey(const Key('amountField')))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addExchangeButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exchangeAmountField')), findsOneWidget);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/wallet/wallet_page_test.dart`
Expected: FAIL — 컴파일 에러(`wallet_page.dart` 없음)

- [ ] **Step 3: `wallet_entry_list.dart` 작성**

`app/lib/features/wallet/widgets/wallet_entry_list.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../data/wallet_database.dart';
import '../domain/currency_info.dart';
import '../domain/expense_category.dart';
import '../domain/month_day.dart';
import '../domain/wallet_entries.dart';

/// 날짜별 기록 목록(설계 §5.2-5). 지출의 원화는 기록 시점 환율로 고정하고,
/// 환전의 원화는 현재 환율로 계속 바뀐다(설계 §5.3).
class WalletEntryList extends StatelessWidget {
  const WalletEntryList({
    super.key,
    required this.entries,
    required this.currency,
    this.currentKrwPerUnit,
    required this.onTapExpense,
    required this.onTapExchange,
    required this.onLongPressExpense,
    required this.onLongPressExchange,
  });

  final List<WalletEntry> entries;
  final CurrencyInfo currency;
  final double? currentKrwPerUnit;
  final ValueChanged<ExpenseRow> onTapExpense;
  final ValueChanged<ExchangeRow> onTapExchange;
  final ValueChanged<ExpenseRow> onLongPressExpense;
  final ValueChanged<ExchangeRow> onLongPressExchange;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '아직 기록이 없습니다. 아래 버튼으로 지출이나 환전을 기록해 보세요.',
          style: AppTextStyles.caption,
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (day, dayEntries) in groupByDate(entries)) ...[
          const SizedBox(height: 10),
          SectionLabel(formatMonthDay(day)),
          for (final entry in dayEntries) _row(entry),
        ],
      ],
    );
  }

  Widget _row(WalletEntry entry) {
    switch (entry) {
      case ExpenseEntry(:final row):
        final category = ExpenseCategory.fromCode(row.category);
        final rateAtEntry = row.krwPerUnitAtEntry;
        return _EntryRow(
          key: Key('entry_expense_${row.id}'),
          kind: category.labelKo,
          title: row.memo.isEmpty ? category.labelKo : row.memo,
          amount: currency.format(row.amountMinor),
          krw: rateAtEntry == null
              ? '환율 없음'
              : '≈ ${formatKrw(currency.toKrw(row.amountMinor, rateAtEntry))}',
          onTap: () => onTapExpense(row),
          onLongPress: () => onLongPressExpense(row),
        );
      case ExchangeEntry(:final row):
        final rate = currentKrwPerUnit;
        return _EntryRow(
          key: Key('entry_exchange_${row.id}'),
          kind: '환전',
          title: row.memo.isEmpty ? '환전' : row.memo,
          amount: '+${currency.format(row.amountMinor)}',
          krw: rate == null ? '' : '≈ ${formatKrw(currency.toKrw(row.amountMinor, rate))}',
          onTap: () => onTapExchange(row),
          onLongPress: () => onLongPressExchange(row),
        );
    }
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.kind,
    required this.title,
    required this.amount,
    required this.krw,
    required this.onTap,
    required this.onLongPress,
  });

  final String kind;
  final String title;
  final String amount;
  final String krw;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
        ),
        child: Row(
          children: [
            SizedBox(width: 44, child: Text(kind, style: AppTextStyles.chip)),
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(amount, style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
                if (krw.isNotEmpty) Text(krw, style: AppTextStyles.caption),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: `wallet_page.dart` 작성**

`app/lib/features/wallet/wallet_page.dart`:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/country_detail_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import 'data/exchange_rate.dart';
import 'data/wallet_database.dart';
import 'data/wallet_rate.dart';
import 'domain/currency_info.dart';
import 'domain/expense_category.dart';
import 'domain/wallet_entries.dart';
import 'domain/wallet_summary.dart';
import 'widgets/balance_card.dart';
import 'widgets/exchange_form_sheet.dart';
import 'widgets/expense_form_sheet.dart';
import 'widgets/rate_banner.dart';
import 'widgets/wallet_entry_list.dart';

/// 나라별 지갑(여행 가계부) 화면 — 지갑·환율 알림 설계 §5.2.
/// 준비물 탭의 `지갑` 카드에서 `/checklist/wallet?iso=JP`로 들어온다. 기록은 기기에만 저장한다.
class WalletPage extends ConsumerStatefulWidget {
  const WalletPage({super.key, required this.isoAlpha2});

  final String isoAlpha2;

  @override
  ConsumerState<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends ConsumerState<WalletPage> {
  /// 카테고리 필터. null이면 전체(지출+환전).
  ExpenseCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(countryDetailProvider(widget.isoAlpha2));
    return detailAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Notice(title: '지갑', message: '국가 정보를 불러오지 못했습니다: $e'),
      data: (detail) {
        final code = detail.currencyCode?.trim();
        if (code == null || code.isEmpty) {
          return _Notice(
            title: '${detail.nameKo} 지갑',
            message: '이 나라의 통화 정보가 없어 지갑을 쓸 수 없습니다.',
          );
        }
        return _wallet(detail, currencyInfoOf(code));
      },
    );
  }

  Widget _wallet(CountryDetail detail, CurrencyInfo currency) {
    final iso = widget.isoAlpha2;
    final rate = ref.watch(walletRateProvider(currency.code)).value;
    final expenses = ref.watch(walletExpensesProvider(iso)).value ?? const <ExpenseRow>[];
    final exchanges = ref.watch(walletExchangesProvider(iso)).value ?? const <ExchangeRow>[];
    final summary = WalletSummary.of(expenses: expenses, exchanges: exchanges);
    final krwPerUnit = rate?.rate.krwRate;

    return Column(
      children: [
        _WalletHeader(title: '${detail.nameKo} 지갑', onClear: () => _clear(detail.nameKo)),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(walletRateProvider(currency.code));
              await ref.read(walletRateProvider(currency.code).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              children: [
                RateBanner(currency: currency, snapshot: rate),
                const SizedBox(height: 12),
                BalanceCard(currency: currency, summary: summary, krwPerUnit: krwPerUnit),
                const SizedBox(height: 14),
                _CategoryFilter(
                  currency: currency,
                  summary: summary,
                  selected: _filter,
                  onSelect: (c) => setState(() => _filter = c),
                ),
                WalletEntryList(
                  entries: buildWalletEntries(expenses: expenses, exchanges: exchanges, filter: _filter),
                  currency: currency,
                  currentKrwPerUnit: krwPerUnit,
                  onTapExpense: (row) => _editExpense(currency, row),
                  onTapExchange: (row) => _editExchange(currency, row),
                  onLongPressExpense: (row) => _deleteExpense(row),
                  onLongPressExchange: (row) => _deleteExchange(row),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Row(
            children: [
              Expanded(
                child: PillButton(
                  key: const Key('addExpenseButton'),
                  label: '지출 기록',
                  onPressed: () => _addExpense(currency, rate),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillOutlineButton(
                  key: const Key('addExchangeButton'),
                  label: '환전 기록',
                  onPressed: () => _addExchange(currency),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  WalletDatabase get _db => ref.read(walletDatabaseProvider);

  /// 새 지출은 지금 화면에 보이는 환율로 원화 값을 고정한다(설계 §5.3).
  Future<void> _addExpense(CurrencyInfo currency, RateSnapshot? rate) async {
    final input = await showExpenseFormSheet(context, currency: currency);
    if (input == null) return;
    await _db.addExpense(
      isoAlpha2: widget.isoAlpha2,
      currencyCode: currency.code,
      category: input.category.code,
      amountMinor: input.amountMinor,
      krwPerUnitAtEntry: rate?.rate.krwRate,
      memo: input.memo,
      spentOn: input.spentOn,
    );
  }

  /// 수정해도 기록 시점 환율(krwPerUnitAtEntry)은 그대로 둔다.
  Future<void> _editExpense(CurrencyInfo currency, ExpenseRow row) async {
    final input = await showExpenseFormSheet(context, currency: currency, initial: row);
    if (input == null) return;
    await _db.updateExpense(row.copyWith(
      category: input.category.code,
      amountMinor: input.amountMinor,
      memo: input.memo,
      spentOn: input.spentOn,
    ));
  }

  Future<void> _addExchange(CurrencyInfo currency) async {
    final input = await showExchangeFormSheet(context, currency: currency);
    if (input == null) return;
    await _db.addExchange(
      isoAlpha2: widget.isoAlpha2,
      currencyCode: currency.code,
      amountMinor: input.amountMinor,
      krwPaid: input.krwPaid,
      memo: input.memo,
      exchangedOn: input.exchangedOn,
    );
  }

  Future<void> _editExchange(CurrencyInfo currency, ExchangeRow row) async {
    final input = await showExchangeFormSheet(context, currency: currency, initial: row);
    if (input == null) return;
    await _db.updateExchange(row.copyWith(
      amountMinor: input.amountMinor,
      krwPaid: Value(input.krwPaid),
      memo: input.memo,
      exchangedOn: input.exchangedOn,
    ));
  }

  Future<void> _deleteExpense(ExpenseRow row) async {
    if (await _confirm('기록 삭제', '이 지출 기록을 삭제할까요?')) {
      await _db.deleteExpense(row.id);
    }
  }

  Future<void> _deleteExchange(ExchangeRow row) async {
    if (await _confirm('기록 삭제', '이 환전 기록을 삭제할까요?')) {
      await _db.deleteExchange(row.id);
    }
  }

  Future<void> _clear(String countryName) async {
    if (await _confirm('지갑 비우기', '$countryName 지갑의 지출·환전 기록을 모두 지울까요? 되돌릴 수 없습니다.')) {
      await _db.clearWallet(widget.isoAlpha2);
    }
  }

  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('삭제')),
        ],
      ),
    );
    return ok ?? false;
  }
}

/// 뒤로가기 + 제목 + 메뉴(지갑 비우기). 비자 결과 화면 헤더와 같은 모양이다.
class _WalletHeader extends StatelessWidget {
  const _WalletHeader({required this.title, this.onClear});

  final String title;
  final VoidCallback? onClear;

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
          if (onClear != null)
            PopupMenuButton<String>(
              key: const Key('walletMenu'),
              icon: const Icon(Icons.more_vert, color: AppColors.textBody),
              onSelected: (_) => onClear!(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'clear', child: Text('지갑 비우기')),
              ],
            ),
        ],
      ),
    );
  }
}

/// 카테고리 필터(설계 §5.2-4). 각 칩에 그 카테고리의 지출 합계를 붙인다.
class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({
    required this.currency,
    required this.summary,
    required this.selected,
    required this.onSelect,
  });

  final CurrencyInfo currency;
  final WalletSummary summary;
  final ExpenseCategory? selected;
  final ValueChanged<ExpenseCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterPill(
            key: const Key('filter_ALL'),
            label: '전체',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final c in ExpenseCategory.values) ...[
            const SizedBox(width: 8),
            FilterPill(
              key: Key('filter_${c.code}'),
              label: '${c.labelKo} ${currency.format(summary.spentByCategory[c]!)}',
              selected: selected == c,
              onTap: () => onSelect(c),
            ),
          ],
        ],
      ),
    );
  }
}

/// 지갑을 쓸 수 없을 때의 안내(헤더 + 가운데 문구).
class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _WalletHeader(title: title),
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

- [ ] **Step 5: 라우트 추가**

`app/lib/router.dart`

(a) import 목록에 추가한다(알파벳 순서 자리, `features/visa/visa_result_page.dart` 다음):

```dart
import 'features/wallet/wallet_page.dart';
```

(b) `AppRoutes`의 `static const groupLocation = '/group/location';` 다음 줄에 추가한다:

```dart

  /// 나라별 지갑. 준비물 탭 아래 화면이라 경로를 /checklist로 시작해 탭바의 준비물 탭이 켜진 채로 둔다.
  static const wallet = '/checklist/wallet';

  static String walletOf(String isoAlpha2) => '$wallet?iso=$isoAlpha2';
```

(c) `ShellRoute`의 `routes` 목록에서 `GoRoute(path: AppRoutes.checklist, builder: (_, _) => const ChecklistPage()),` 다음 줄에 추가한다:

```dart
          GoRoute(
            path: AppRoutes.wallet,
            builder: (_, state) =>
                WalletPage(isoAlpha2: state.uri.queryParameters['iso'] ?? 'VN'),
          ),
```

- [ ] **Step 6: 통과 확인**

Run: `flutter test test/wallet/wallet_page_test.dart`
Expected: PASS (6)

Run: `flutter test`
Expected: 전체 통과(기존 202개 + 이번 단계 테스트). 실패하면 이번 변경과의 관련성을 확인한다.

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 7: 커밋**

```bash
git add lib/features/wallet/widgets/wallet_entry_list.dart lib/features/wallet/wallet_page.dart \
  lib/router.dart test/wallet/wallet_page_test.dart
git commit -m "feat(app): 나라별 지갑 화면과 라우트 추가"
```

---

### Task 7: 준비물 탭 — 지갑 카드와 보조배터리 체크리스트 행

**Files:**
- Create: `app/lib/features/checklist/data/power_bank_item.dart`
- Modify: `app/lib/features/checklist/checklist_page.dart`
- Test: `app/test/checklist/power_bank_item_test.dart`, `app/test/checklist/checklist_page_test.dart`

**Interfaces:**
- Consumes: `ChecklistItem(id, category, title, description, priority)`(`lib/core/network/checklist_api.dart`), `checklistProvider`, `countryDetailProvider`, `sharedPreferencesProvider`, Task 6 `AppRoutes.walletOf(String)`
- Produces:
  - `const int powerBankChecklistId = -1`
  - `List<ChecklistItem> withPowerBankItem(List<ChecklistItem> items, int? whLimit)`
  - 준비물 화면 상단 카드 키 `walletCard`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/checklist/power_bank_item_test.dart`:

```dart
import 'package:app/core/network/checklist_api.dart';
import 'package:app/features/checklist/data/power_bank_item.dart';
import 'package:flutter_test/flutter_test.dart';

ChecklistItem _item(int id, String category) =>
    ChecklistItem(id: id, category: category, title: 't$id', priority: id);

void main() {
  test('POWER 섹션의 마지막 항목 바로 뒤에 넣는다', () {
    final items = [_item(1, 'DOCUMENT'), _item(2, 'POWER'), _item(3, 'POWER'), _item(4, 'MONEY')];

    final result = withPowerBankItem(items, 100);

    expect(result.map((i) => i.id).toList(), [1, 2, 3, powerBankChecklistId, 4]);
    final bank = result[3];
    expect(bank.category, 'POWER');
    expect(bank.title, '보조배터리 기내 반입 (100Wh 이하)');
    expect(bank.description, '위탁 수하물 불가 · 기내 반입만 가능');
  });

  test('POWER 항목이 없으면 맨 끝에 붙여 새 섹션이 된다', () {
    final result = withPowerBankItem([_item(1, 'DOCUMENT')], 160);

    expect(result.map((i) => i.id).toList(), [1, powerBankChecklistId]);
    expect(result.last.title, '보조배터리 기내 반입 (160Wh 이하)');
  });

  test('한도 정보가 없으면 그대로 둔다', () {
    final items = [_item(1, 'POWER')];

    expect(withPowerBankItem(items, null), same(items));
  });
}
```

`app/test/checklist/checklist_page_test.dart`:

```dart
import 'package:app/core/network/checklist_api.dart';
import 'package:app/core/network/country_detail_api.dart';
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/checklist/checklist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpChecklist(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: '/checklist',
    routes: [
      GoRoute(path: '/checklist', builder: (_, _) => const Scaffold(body: ChecklistPage())),
      GoRoute(
        path: '/checklist/wallet',
        builder: (_, state) => Scaffold(body: Text('wallet ${state.uri.queryParameters['iso']}')),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      countryDetailProvider.overrideWith((ref, iso) async => const CountryDetail(
            isoAlpha2: 'VN',
            nameKo: '베트남',
            plugTypes: 'A, C, G',
            voltageV: 220,
            currencyCode: 'VND',
            cardAcceptance: 'LOW',
            powerBankWhLimit: 100,
          )),
      checklistProvider.overrideWith((ref, iso) async => const [
            ChecklistItem(id: 10, category: 'POWER', title: '멀티어댑터', priority: 10),
            ChecklistItem(id: 20, category: 'MONEY', title: '환전', priority: 80),
          ]),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('상단 세 번째 카드는 지갑이고, 누르면 그 나라 지갑으로 간다', (tester) async {
    await _pumpChecklist(tester);

    expect(find.text('지갑'), findsOneWidget);
    expect(find.text('VND ›'), findsOneWidget);
    expect(find.text('보조배터리'), findsNothing);

    await tester.tap(find.byKey(const Key('walletCard')));
    await tester.pumpAndSettle();

    expect(find.text('wallet VN'), findsOneWidget);
  });

  testWidgets('보조배터리는 전자기기 섹션의 체크리스트 행이 되고, 체크하면 진행률에 반영된다', (tester) async {
    await _pumpChecklist(tester);

    expect(find.text('보조배터리 기내 반입 (100Wh 이하)'), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget);

    await tester.tap(find.text('보조배터리 기내 반입 (100Wh 이하)'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/checklist/power_bank_item_test.dart test/checklist/checklist_page_test.dart`
Expected: FAIL — `power_bank_item.dart` 없음(컴파일 에러)

- [ ] **Step 3: `power_bank_item.dart` 작성**

`app/lib/features/checklist/data/power_bank_item.dart`:

```dart
import '../../../core/network/checklist_api.dart';

/// 보조배터리 행의 예약 id. 서버 준비물 템플릿 id(양수)와 겹치지 않게 음수를 쓴다.
/// 체크 상태는 다른 준비물처럼 ChecklistCheckedStore에 이 id로 저장된다.
const int powerBankChecklistId = -1;

/// 국가 정보의 보조배터리 기내 반입 한도(Wh)를 체크리스트 행으로 만들어 끼워 넣는다(설계 §5.1).
/// 서버 준비물 템플릿에는 없는 항목이라 앱에서 만든다. `POWER` 섹션 맨 뒤에 넣고,
/// `POWER` 항목이 없으면 맨 끝에 붙여 새 섹션이 되게 한다. 한도 정보가 없으면 목록을 그대로 돌려준다.
List<ChecklistItem> withPowerBankItem(List<ChecklistItem> items, int? whLimit) {
  if (whLimit == null) return items;
  final item = ChecklistItem(
    id: powerBankChecklistId,
    category: 'POWER',
    title: '보조배터리 기내 반입 (${whLimit}Wh 이하)',
    description: '위탁 수하물 불가 · 기내 반입만 가능',
    priority: 0,
  );
  final lastPower = items.lastIndexWhere((i) => i.category == 'POWER');
  final result = [...items];
  if (lastPower == -1) {
    result.add(item);
  } else {
    result.insert(lastPower + 1, item);
  }
  return result;
}
```

- [ ] **Step 4: 준비물 화면 수정**

`app/lib/features/checklist/checklist_page.dart`

(a) import 목록을 다음으로 바꾼다(`go_router`, `router.dart`, `power_bank_item.dart` 추가):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/checklist_api.dart';
import '../../core/network/country_api.dart';
import '../../core/network/country_detail_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../../router.dart';
import 'data/checklist_providers.dart';
import 'data/power_bank_item.dart';
```

(b) `build()` 안의 다음 줄을:

```dart
                  data: (detail) => _CountryInfoRow(detail: detail),
```

다음으로 바꾼다:

```dart
                  data: (detail) => _CountryInfoRow(
                    detail: detail,
                    onOpenWallet: () => context.push(AppRoutes.walletOf(_isoAlpha2)),
                  ),
```

(c) 같은 `build()`의 `checklistAsync.when(` 블록에서 다음 부분을:

```dart
                  data: (items) {
                    final checkedCount =
                        items.where((i) => checkedIds.contains(i.id)).length;
```

다음으로 바꾼다:

```dart
                  data: (serverItems) {
                    // 보조배터리는 상단 카드에서 체크리스트 행으로 옮겼다(지갑·환율 알림 설계 §5.1).
                    final items = withPowerBankItem(
                        serverItems, detailAsync.value?.powerBankWhLimit);
                    final checkedCount =
                        items.where((i) => checkedIds.contains(i.id)).length;
```

(d) `_CountryInfoRow` 클래스 전체를 다음으로 바꾼다:

```dart
class _CountryInfoRow extends StatelessWidget {
  const _CountryInfoRow({required this.detail, required this.onOpenWallet});

  final CountryDetail detail;
  final VoidCallback onOpenWallet;

  @override
  Widget build(BuildContext context) {
    final plug = detail.plugTypes != null && detail.voltageV != null
        ? '${detail.plugTypes}형 ${detail.voltageV}V'
        : '정보 없음';
    final payment = detail.paymentTier?.labelKo ?? '정보 없음';
    final currency = detail.currencyCode?.trim();

    return Row(
      children: [
        Expanded(child: _CountryInfoCard(label: '플러그', value: plug)),
        const SizedBox(width: 8),
        Expanded(child: _CountryInfoCard(label: '결제', value: payment)),
        const SizedBox(width: 8),
        Expanded(
          child: _CountryInfoCard(
            key: const Key('walletCard'),
            label: '지갑',
            value: currency == null || currency.isEmpty ? '정보 없음' : '$currency ›',
            onTap: onOpenWallet,
          ),
        ),
      ],
    );
  }
}
```

(e) `_CountryInfoCard` 클래스 전체를 다음으로 바꾼다(누를 수 있는 카드 지원):

```dart
class _CountryInfoCard extends StatelessWidget {
  const _CountryInfoCard({super.key, required this.label, required this.value, this.onTap});

  final String label;
  final String value;

  /// 있으면 카드를 누를 수 있다(지갑 카드). 누를 수 있는 카드는 값 글자를 파란색으로 보인다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderLight),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.placeholderPrimary,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: AppTextStyles.caption),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Noto Sans KR',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: onTap == null ? AppColors.ink : AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 통과 확인**

Run: `flutter test test/checklist/`
Expected: PASS (기존 checklist 테스트 + 새 3 + 2)

Run: `flutter test`
Expected: 전체 통과

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 6: 커밋**

```bash
git add lib/features/checklist/data/power_bank_item.dart lib/features/checklist/checklist_page.dart \
  test/checklist/power_bank_item_test.dart test/checklist/checklist_page_test.dart
git commit -m "feat(app): 준비물 탭에 지갑 카드를 두고 보조배터리를 체크리스트로 옮긴다"
```

---

### Task 8: 실기기 확인

코드 변경은 없다. 1단계 서버를 띄우고 실제 폰에서 지갑을 끝까지 써 본다.

- [ ] **Step 1: 서버 기동**: `server/`에서 `./gradlew bootRun --args='--spring.profiles.active=dev'` → 로그에 `Started ServerApplication`
- [ ] **Step 2: 앱 실행**: `app/`에서 `flutter run --dart-define=API_BASE_URL=http://<PC LAN IP>:8080` (폰과 PC가 같은 Wi-Fi, VPN 끔)
- [ ] **Step 3: 확인 목록** (모두 통과해야 2단계 완료)
  1. 준비물 탭 상단 카드가 `플러그 · 결제 · 지갑`이고, `지갑` 값이 통화 코드(예: `VND ›`)
  2. 전자기기 섹션에 `보조배터리 기내 반입 (NNWh 이하)` 행이 있고 체크된다
  3. `지갑` → `{나라} 지갑` 화면, 하단 탭바는 준비물 탭이 켜진 채
  4. 일본으로 나라 변경 후 지갑: 배너 `100엔 = 8xx.xx원`, 등락 화살표·색, `고시 · 한국수출입은행`
  5. 베트남 지갑: 배너 `1,000동 = 5x.xx원`, `참고환율 · Rates By Exchange Rate API`
  6. 환전 기록(받은 금액 + 낸 원화) → 남은 돈·원화 환산·평가손익 표시
  7. 식비·숙박·교통·관광·기타 지출 기록 → 합계·필터·목록(날짜 묶음) 반영, 기타 메모 힌트 `여행자보험, eSIM 등`
  8. 행 탭 → 수정, 길게 누르기 → 삭제 확인 후 삭제
  9. ⋮ → `지갑 비우기` → 그 나라 기록만 사라짐
  10. 아래로 당겨 새로고침 동작. 비행기 모드에서 지갑을 다시 열어도 마지막 환율과 고시일이 보임

---

## Self-Review

- **Spec §5.1**: 지갑 카드(Task 7 (d)(e)), `/checklist/wallet?iso=` 이동(Task 6 라우트 + Task 7 (b)), 보조배터리 행 생성·생략·POWER 섹션 없을 때 새 섹션·예약 키 체크(Task 7 `withPowerBankItem` + 위젯 테스트).
- **§5.2 화면 7요소**: 헤더·메뉴 지갑 비우기(Task 6 `_WalletHeader`·`_clear`), 배너(Task 4), 남은 돈 카드·평가손익(Task 4), 카테고리 필터 + 합계(Task 6 `_CategoryFilter`), 날짜별 목록(Task 3 `groupByDate` + Task 6 `WalletEntryList`), 하단 버튼 → 바텀시트(Task 5·6), 탭 수정·길게 눌러 삭제(Task 6).
- **§5.3**: 지출 원화는 `krwPerUnitAtEntry` 고정(Task 3 컬럼, Task 6 `_addExpense`·`_editExpense`가 유지), 환전은 현재 환율(Task 6 `WalletEntryList.currentKrwPerUnit`, Task 4 카드). 카테고리 코드 5종·기타 힌트(Task 1).
- **§5.4**: 별도 `wallet.sqlite`(Task 3), 최소단위 정수(Task 1 `parseToMinor`/`format`/`toKrw`), 표시 단위 규칙(Task 1 `displayUnit`).
- **§5.5**: `rateCache.<CUR>`(Task 2 `RateCache`), 캐시 먼저 → 서버(Task 2 `loadWalletRate`), 당겨서 새로고침(Task 6 `RefreshIndicator`), 오프라인 확인(Task 8).
- **§5.6 테스트**: DB(Task 3), 통화·포맷·단위(Task 1), 화면(Task 6), 준비물(Task 7).
- **타입 일관성**: `ExpenseRow`/`ExchangeRow`, `RateSnapshot`, `WalletSummary.of`, `buildWalletEntries`, `groupByDate`, `showExpenseFormSheet`/`ExpenseInput`, `showExchangeFormSheet`/`ExchangeInput`, `walletRateProvider`, `walletExpensesProvider`, `walletExchangesProvider`, `AppRoutes.walletOf`가 정의한 태스크와 쓰는 태스크에서 같은 이름·인자다.
