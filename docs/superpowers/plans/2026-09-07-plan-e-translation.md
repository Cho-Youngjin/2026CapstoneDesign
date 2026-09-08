# Plan E — 앱: 텍스트/OCR/음성 번역 + 상황별 문구 프리셋 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phase 0에서 빈 껍데기로 잡힌 `TranslatePage`(`app/lib/features/translate/translate_page.dart`)를 텍스트 번역 · 카메라 OCR 번역 · 음성 번역 3종과 상황별 문구 프리셋(입국심사/식당/교통/응급)으로 채운다. 목적지 국가 언어가 기본 대상 언어로 자동 선택된다.

**Architecture:** 세 기능은 `TranslatePage` 안의 탭 3개(텍스트 / 카메라 / 음성)로 나뉜다. 셋 다 공통으로 `TranslateApi`(서버 `POST /api/translate` 프록시 — Plan A 담당, 여기서는 계약만 소비) 하나를 호출해 번역을 수행한다. OCR은 `google_mlkit_text_recognition`으로, 음성은 `speech_to_text`/`flutter_tts`로 텍스트를 만들거나 읽어주며, 이 셋은 온디바이스라 서버를 거치지 않는다. Phase 0가 `AuthRepository`·`TokenVerifier`에 썼던 것과 같은 방식으로, 서드파티 플러그인은 얇은 인터페이스 뒤에 두어(`TextRecognizerService`, `SpeechRecognitionService`, `TextToSpeechService`) 실제 카메라·마이크 없이도 로직을 테스트한다.

**Tech Stack:** Flutter 3.x / Riverpod / dio(`apiClientProvider`, Task 9 산출물) · `google_mlkit_text_recognition`(OCR, 온디바이스) · `image_picker`(카메라 촬영) · `speech_to_text` / `flutter_tts`(음성, 온디바이스) · `permission_handler`(카메라·마이크 권한)

**Spec:** `docs/superpowers/specs/2026-09-06-overseas-travel-app-design.md` §4(Google Cloud Translation, NMT 기본값 + 인터페이스 추상화), §6-⑤(번역 기능)

## Global Constraints

이 계획서는 Phase 0 계획서(`docs/superpowers/plans/2026-09-06-phase0-foundation.md`)가 이미 구현되어 있다고 가정한다. 아래는 그 계획서의 제약을 그대로 이어받는다.

- **모노레포 구조**: `app/`(Flutter), `server/`(Spring Boot), `docs/`.
- **Android 전용.** iOS 빌드 설정은 손대지 않는다.
- **비밀정보를 커밋하지 않는다.** 이 계획서는 Google Translation API 키를 앱에 두지 않는다 — 모든 번역 호출은 서버 프록시(`POST /api/translate`)를 거치며, 앱은 Firebase ID Token만 첨부한다(스펙 §3 "외부 API 프록시" 근거와 동일).
- **브랜치 전략**: `main` / `develop` / `feature/*`. 모든 작업은 `feature/*`에서 시작해 `develop`으로 PR한다. PR은 2인 승인.
- **매주 금요일 `develop` 머지 필수.**
- **패키지 루트**: `com.travelfootsteps`
- **서버 포트**: 8080. 안드로이드 에뮬레이터에서 호스트는 `10.0.2.2` (Task 9의 `resolveBaseUrl`이 이미 처리한다).
- **화면은 서드파티 SDK를 직접 호출하지 않는다** — Phase 0의 `AuthRepository` 추상화 규칙과 같은 원칙을 번역 3종에도 적용한다. OCR·STT·TTS는 각각 인터페이스 뒤에 두고, 화면은 인터페이스만 안다.
- **OCR·STT·TTS는 전부 온디바이스이며 추가 과금이 없다** (스펙 §4, §6-⑤). 번역 텍스트 호출(`POST /api/translate`)만 서버의 Google Cloud Translation 무료 티어(월 50만 자)를 소비한다.

## 이 계획서가 가정하는 인터페이스 (Phase 0 산출물)

- `apiClientProvider` — `Provider<Dio>` (`app/lib/core/network/api_client.dart`). Firebase ID Token이 `AuthInterceptor`로 자동 첨부된다.
- `TranslatePage` — `app/lib/features/translate/translate_page.dart`, 현재 `Center(child: Text('번역'))` 껍데기. 이 계획서가 내용을 채운다.
- `AppRoutes.translate` = `/translate` (라우팅은 이미 연결되어 있음, 변경하지 않는다).

## 이 계획서가 서버에 기대하는 계약 (Plan A가 구현 예정)

Plan A가 아직 작성되지 않았으므로, 스펙 §7의 `POST /api/translate` 목록 항목을 아래와 같이 구체화해서 가정한다. **Plan A 작성 시 이 계약과 다르면 Plan A 쪽을 이 계약에 맞추거나, R1과 R4가 합의해 이 문서를 갱신한다.**

```
POST /api/translate
Authorization: Bearer <Firebase ID Token>   ← apiClientProvider가 자동 첨부
Content-Type: application/json

Request:
{
  "text": "안녕하세요",
  "targetLanguage": "en",       // BCP-47/ISO 639-1 코드
  "sourceLanguage": "ko"        // 선택. 생략하면 서버가 자동 감지
}

Response 200:
{
  "translatedText": "Hello",
  "detectedSourceLanguage": "ko"  // sourceLanguage를 생략했을 때만 값이 있을 수 있음
}
```

---

## File Structure

```
app/
├── lib/
│   ├── core/
│   │   └── network/
│   │       └── translate_api.dart          POST /api/translate 클라이언트 + 모델
│   └── features/
│       └── translate/
│           ├── translate_page.dart          MODIFY — 3탭(텍스트/카메라/음성) 셸
│           ├── language/
│           │   └── target_language.dart     언어 목록, 국가→언어 매핑, 선택 상태
│           ├── presets/
│           │   └── phrase_presets.dart      상황별 문구 정적 데이터
│           ├── text/
│           │   ├── text_translate_controller.dart   번역 요청 상태(StateNotifier)
│           │   └── text_translate_tab.dart           텍스트 번역 + 프리셋 UI
│           ├── ocr/
│           │   ├── text_recognizer_service.dart      OCR 인터페이스 + ML Kit 구현체
│           │   └── ocr_translate_tab.dart             촬영 → 인식 → 번역 → 오버레이 UI
│           └── voice/
│               ├── speech_services.dart               STT/TTS 인터페이스 + 구현체
│               └── voice_translate_tab.dart           양방향 대화 모드 UI
└── test/
    └── translate/
        ├── target_language_test.dart
        ├── phrase_presets_test.dart
        ├── translate_api_test.dart
        ├── text_translate_controller_test.dart
        ├── ocr_orchestration_test.dart
        └── voice_orchestration_test.dart
```

**분리 원칙**: `core/network/translate_api.dart`는 서버와의 계약만 알고 UI를 모른다(Task 9의 `country_api.dart`와 같은 위치·역할). `features/translate/` 아래는 탭별로 폴더를 나눠, 한 탭의 변경이 다른 탭 파일을 건드리지 않게 한다. `language/`와 `presets/`는 세 탭이 공유하므로 별도 폴더로 뺀다.

## 담당과 순서에 대해

R4(경험이 적은 팀원) 담당이며, 스펙 §8의 결정("복잡한 상태관리가 적은 패키지 조합 성격")과 §9 일정표(OCR·음성은 W9로 늦게 배치, 텍스트 번역은 W6~8)를 그대로 따른다.

| Task | 내용 | 난이도 | 시기 |
|---|---|---|---|
| 1 | 언어 선택 모델 + 목적지 언어 매핑 | 낮음 (순수 Dart) | W6 |
| 2 | 상황별 문구 프리셋 정적 데이터 | 낮음 (순수 Dart) | W6 |
| 3 | 번역 API 클라이언트 | 낮음~중간 (dio 계약 소비) | W6 |
| 4 | 텍스트 번역 화면 (M3 게이트 대상) | 중간 (Riverpod 상태관리 첫 도입) | W7~8 |
| 5 | 카메라 OCR 번역 | 중간~높음 (플러그인 + 권한) | W9 |
| 6 | 음성 번역 (양방향 대화 모드) | 높음 (플러그인 2개 조합 + 대화 상태) | W9 |

Task 1~4가 스펙 §9의 **M3 게이트**(Phase 2, W8말 — "6개 기능이 전부 기본 형태로 동작")에서 요구하는 "텍스트 번역"에 해당한다. Task 5~6은 Phase 3(W9~10)에 배치된다.

---

### Task 1: 언어 선택 모델 + 목적지 언어 자동 설정

**Files:**
- Create: `app/lib/features/translate/language/target_language.dart`
- Test: `app/test/translate/target_language_test.dart`

**Interfaces:**
- Consumes: 없음 (순수 Dart, 첫 태스크)
- Produces:
  - `class LanguageOption { final String code; final String labelKo; }` — `code`는 BCP-47/ISO 639-1
  - `const List<LanguageOption> kSupportedLanguages` — 앱이 지원하는 대상 언어 전체 목록
  - `String? languageCodeForCountry(String isoAlpha2)` — Tier A 20개국(스펙 §5) ISO 코드 → 언어 코드 매핑. 매핑이 없으면 `null`
  - `class TargetLanguageNotifier extends StateNotifier<LanguageOption>` — 초기값 `kSupportedLanguages`의 영어(`en`). `setFromCountry(String isoAlpha2)` 호출 시 매핑되는 언어로 바꾸고, 매핑이 없으면 현재 상태를 유지한다. `setManually(LanguageOption)`로 사용자가 직접 바꿀 수 있다
  - `targetLanguageProvider` — `StateNotifierProvider<TargetLanguageNotifier, LanguageOption>`
  - Task 4(텍스트 번역), Task 5(OCR), Task 6(음성)이 전부 `targetLanguageProvider`를 대상 언어로 사용한다

> **여행지 국가와의 연동에 대해**: Plan B(여행계획)가 아직 작성되지 않아 "현재 여행의 목적지 국가"를 앱 전체에서 어떻게 노출할지(예: `currentTripProvider`)가 정해져 있지 않다. 이 계획서는 `setFromCountry(isoAlpha2)`라는 진입점만 만들어 두고, Plan B의 여행 데이터 provider가 준비되면 `ref.listen`으로 한 줄 연결하면 되도록 열어 둔다. Task 4에서는 국가 선택이 없는 상태를 가정해 **수동 언어 선택 드롭다운을 항상 함께 제공**하므로, 이 연동이 W9까지 없어도 기능은 완결된다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/translate/target_language_test.dart`:

```dart
import 'package:app/features/translate/language/target_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('languageCodeForCountry', () {
    test('Tier A 국가는 언어 코드를 반환한다', () {
      expect(languageCodeForCountry('JP'), 'ja');
      expect(languageCodeForCountry('VN'), 'vi');
      expect(languageCodeForCountry('FR'), 'fr');
      expect(languageCodeForCountry('US'), 'en');
    });

    test('매핑이 없는 국가는 null을 반환한다', () {
      expect(languageCodeForCountry('ZZ'), isNull);
    });
  });

  group('kSupportedLanguages', () {
    test('중복 코드가 없다', () {
      final codes = kSupportedLanguages.map((l) => l.code).toSet();
      expect(codes.length, kSupportedLanguages.length);
    });

    test('영어가 포함되어 있다', () {
      expect(kSupportedLanguages.any((l) => l.code == 'en'), isTrue);
    });
  });

  group('TargetLanguageNotifier', () {
    test('초기값은 영어다', () {
      final notifier = TargetLanguageNotifier();
      expect(notifier.state.code, 'en');
    });

    test('매핑되는 국가면 언어를 바꾼다', () {
      final notifier = TargetLanguageNotifier();
      notifier.setFromCountry('JP');
      expect(notifier.state.code, 'ja');
    });

    test('매핑이 없는 국가면 상태를 유지한다', () {
      final notifier = TargetLanguageNotifier();
      notifier.setFromCountry('JP');
      notifier.setFromCountry('ZZ');
      expect(notifier.state.code, 'ja');
    });

    test('수동으로 바꿀 수 있다', () {
      final notifier = TargetLanguageNotifier();
      final french = kSupportedLanguages.firstWhere((l) => l.code == 'fr');
      notifier.setManually(french);
      expect(notifier.state.code, 'fr');
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/translate/target_language_test.dart
```

기대: 컴파일 실패 — `app/features/translate/language/target_language.dart`를 찾을 수 없음.

- [ ] **Step 3: 구현**

`app/lib/features/translate/language/target_language.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LanguageOption {
  const LanguageOption({required this.code, required this.labelKo});

  final String code;
  final String labelKo;
}

const List<LanguageOption> kSupportedLanguages = [
  LanguageOption(code: 'ko', labelKo: '한국어'),
  LanguageOption(code: 'en', labelKo: '영어'),
  LanguageOption(code: 'ja', labelKo: '일본어'),
  LanguageOption(code: 'vi', labelKo: '베트남어'),
  LanguageOption(code: 'th', labelKo: '태국어'),
  LanguageOption(code: 'zh-CN', labelKo: '중국어(간체)'),
  LanguageOption(code: 'zh-TW', labelKo: '중국어(번체)'),
  LanguageOption(code: 'fr', labelKo: '프랑스어'),
  LanguageOption(code: 'it', labelKo: '이탈리아어'),
  LanguageOption(code: 'es', labelKo: '스페인어'),
  LanguageOption(code: 'de', labelKo: '독일어'),
  LanguageOption(code: 'tr', labelKo: '튀르키예어'),
  LanguageOption(code: 'cs', labelKo: '체코어'),
  LanguageOption(code: 'id', labelKo: '인도네시아어'),
];

/// 스펙 §5 Tier A 20개국 → 기본 대상 언어. 매핑이 없으면 null이며,
/// 화면은 이 경우 직전 선택을 유지한다 (Step 3 참고).
const Map<String, String> _countryToLanguage = {
  'JP': 'ja',
  'VN': 'vi',
  'TH': 'th',
  'US': 'en',
  'PH': 'en',
  'CN': 'zh-CN',
  'TW': 'zh-TW',
  'SG': 'en',
  'HK': 'zh-TW',
  'FR': 'fr',
  'IT': 'it',
  'ES': 'es',
  'DE': 'de',
  'GB': 'en',
  'AU': 'en',
  'TR': 'tr',
  'CH': 'de',
  'CZ': 'cs',
  'ID': 'id',
  'CA': 'en',
};

String? languageCodeForCountry(String isoAlpha2) => _countryToLanguage[isoAlpha2];

class TargetLanguageNotifier extends StateNotifier<LanguageOption> {
  TargetLanguageNotifier()
      : super(kSupportedLanguages.firstWhere((l) => l.code == 'en'));

  /// 목적지 국가가 정해지면 호출한다. 매핑이 없으면 상태를 바꾸지 않는다 —
  /// 미검증 매핑으로 잘못된 언어를 고르는 것보다 직전 선택을 지키는 편이 안전하다.
  void setFromCountry(String isoAlpha2) {
    final code = languageCodeForCountry(isoAlpha2);
    if (code == null) return;
    final match = kSupportedLanguages.where((l) => l.code == code);
    if (match.isEmpty) return;
    state = match.first;
  }

  void setManually(LanguageOption option) => state = option;
}

final targetLanguageProvider =
    StateNotifierProvider<TargetLanguageNotifier, LanguageOption>(
  (ref) => TargetLanguageNotifier(),
);
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/translate/target_language_test.dart
```

기대: 전체 PASS.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/translate/language app/test/translate/target_language_test.dart
git commit -m "feat(app): 번역 대상 언어 목록과 목적지 국가 매핑"
```

---

### Task 2: 상황별 문구 프리셋 (입국심사/식당/교통/응급)

**Files:**
- Create: `app/lib/features/translate/presets/phrase_presets.dart`
- Test: `app/test/translate/phrase_presets_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `enum PresetCategory { immigration, restaurant, transport, emergency }` — `labelKo` getter
  - `class PhrasePreset { final PresetCategory category; final String textKo; }`
  - `const List<PhrasePreset> kPhrasePresets` — 카테고리당 최소 4개, 전부 한국어 원문(대상 언어로는 Task 3의 API로 그때그때 번역한다 — 사전 번역해서 정적으로 들고 있지 않는다. 이유: 언어가 14종이라 정적 번역 데이터가 14배로 불어나고, 서버 번역 엔진이 Plan A에서 NMT→LLM으로 교체돼도(스펙 §4) 문구 프리셋 품질이 자동으로 같이 좋아진다)
  - Task 4가 `kPhrasePresets`를 카테고리별로 묶어 칩(chip) UI로 노출한다

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/translate/phrase_presets_test.dart`:

```dart
import 'package:app/features/translate/presets/phrase_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('4개 카테고리 모두 문구가 4개 이상이다', () {
    for (final category in PresetCategory.values) {
      final count =
          kPhrasePresets.where((p) => p.category == category).length;
      expect(count, greaterThanOrEqualTo(4),
          reason: '${category.labelKo}의 문구가 부족하다');
    }
  });

  test('카테고리 라벨이 전부 한국어로 지정되어 있다', () {
    expect(PresetCategory.immigration.labelKo, '입국심사');
    expect(PresetCategory.restaurant.labelKo, '식당');
    expect(PresetCategory.transport.labelKo, '교통');
    expect(PresetCategory.emergency.labelKo, '응급');
  });

  test('빈 문구는 없다', () {
    expect(kPhrasePresets.every((p) => p.textKo.trim().isNotEmpty), isTrue);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/translate/phrase_presets_test.dart
```

기대: 컴파일 실패 — `phrase_presets.dart`를 찾을 수 없음.

- [ ] **Step 3: 구현**

`app/lib/features/translate/presets/phrase_presets.dart`:

```dart
enum PresetCategory { immigration, restaurant, transport, emergency }

extension PresetCategoryLabel on PresetCategory {
  String get labelKo => switch (this) {
        PresetCategory.immigration => '입국심사',
        PresetCategory.restaurant => '식당',
        PresetCategory.transport => '교통',
        PresetCategory.emergency => '응급',
      };
}

class PhrasePreset {
  const PhrasePreset({required this.category, required this.textKo});

  final PresetCategory category;
  final String textKo;
}

const List<PhrasePreset> kPhrasePresets = [
  // 입국심사
  PhrasePreset(category: PresetCategory.immigration, textKo: '여행 목적은 관광입니다.'),
  PhrasePreset(category: PresetCategory.immigration, textKo: '일주일 동안 머무를 예정입니다.'),
  PhrasePreset(category: PresetCategory.immigration, textKo: '숙소는 예약한 호텔입니다.'),
  PhrasePreset(category: PresetCategory.immigration, textKo: '돌아가는 항공권을 가지고 있습니다.'),

  // 식당
  PhrasePreset(category: PresetCategory.restaurant, textKo: '2명 자리 있나요?'),
  PhrasePreset(category: PresetCategory.restaurant, textKo: '이 음식에 땅콩이 들어가나요?'),
  PhrasePreset(category: PresetCategory.restaurant, textKo: '너무 맵지 않게 해주세요.'),
  PhrasePreset(category: PresetCategory.restaurant, textKo: '계산서 주세요.'),

  // 교통
  PhrasePreset(category: PresetCategory.transport, textKo: '이 버스가 공항으로 가나요?'),
  PhrasePreset(category: PresetCategory.transport, textKo: '가장 가까운 지하철역이 어디인가요?'),
  PhrasePreset(category: PresetCategory.transport, textKo: '이 주소로 가주세요.'),
  PhrasePreset(category: PresetCategory.transport, textKo: '요금이 얼마인가요?'),

  // 응급
  PhrasePreset(category: PresetCategory.emergency, textKo: '도와주세요.'),
  PhrasePreset(category: PresetCategory.emergency, textKo: '가장 가까운 병원이 어디인가요?'),
  PhrasePreset(category: PresetCategory.emergency, textKo: '지갑을 잃어버렸어요.'),
  PhrasePreset(category: PresetCategory.emergency, textKo: '경찰을 불러주세요.'),
];
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/translate/phrase_presets_test.dart
```

기대: 전체 PASS.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/translate/presets app/test/translate/phrase_presets_test.dart
git commit -m "feat(app): 상황별 문구 프리셋 정적 데이터"
```

---

### Task 3: 번역 API 클라이언트

**Files:**
- Create: `app/lib/core/network/translate_api.dart`
- Test: `app/test/translate_api_test.dart`

**Interfaces:**
- Consumes: Task 9의 `apiClientProvider`(`Provider<Dio>`, 이미 `AuthInterceptor`가 붙어 있음)
- Produces:
  - `class TranslationResult { final String translatedText; final String? detectedSourceLanguage; }`
  - `class TranslateApi { TranslateApi(this._dio); Future<TranslationResult> translate({required String text, required String targetLanguage, String? sourceLanguage}); }`
  - `translateApiProvider` — `Provider<TranslateApi>`
  - Task 4·5·6이 전부 `translateApiProvider`를 통해서만 번역을 요청한다 (직접 dio를 쓰지 않는다)

- [ ] **Step 1: 실패하는 테스트 작성**

Phase 0의 `api_client_test.dart`가 `RequestInterceptorHandler`를 직접 다뤘던 것과 같은 방식으로, 여기서는 `Dio`에 가짜 `HttpClientAdapter`를 꽂아 네트워크 없이 테스트한다.

`app/test/translate_api_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/network/translate_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실제 네트워크 없이 고정 응답을 돌려주는 테스트용 어댑터.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic> body;
  RequestOptions? capturedRequest;
  Map<String, dynamic>? capturedBody;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedRequest = options;
    if (requestStream != null) {
      final bytes = await requestStream.expand((e) => e).toList();
      capturedBody = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    }
    final payload = utf8.encode(jsonEncode(body));
    return ResponseBody.fromBytes(
      payload,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  group('TranslateApi.translate', () {
    test('번역 결과를 파싱한다', () async {
      final adapter = _StubAdapter(200, {
        'translatedText': 'Hello',
        'detectedSourceLanguage': 'ko',
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;
      final api = TranslateApi(dio);

      final result = await api.translate(text: '안녕하세요', targetLanguage: 'en');

      expect(result.translatedText, 'Hello');
      expect(result.detectedSourceLanguage, 'ko');
    });

    test('/api/translate로 텍스트와 대상 언어를 보낸다', () async {
      final adapter = _StubAdapter(200, {'translatedText': 'Bonjour'});
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;
      final api = TranslateApi(dio);

      await api.translate(text: '안녕', targetLanguage: 'fr', sourceLanguage: 'ko');

      expect(adapter.capturedRequest!.path, '/api/translate');
      expect(adapter.capturedRequest!.method, 'POST');
      expect(adapter.capturedBody!['text'], '안녕');
      expect(adapter.capturedBody!['targetLanguage'], 'fr');
      expect(adapter.capturedBody!['sourceLanguage'], 'ko');
    });

    test('sourceLanguage를 생략하면 요청 본문에 넣지 않는다', () async {
      final adapter = _StubAdapter(200, {'translatedText': 'Hi'});
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;
      final api = TranslateApi(dio);

      await api.translate(text: 'hi', targetLanguage: 'en');

      expect(adapter.capturedBody!.containsKey('sourceLanguage'), isFalse);
    });

    test('서버 오류(500)면 예외를 던진다', () async {
      final adapter = _StubAdapter(500, {'message': 'internal error'});
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;
      final api = TranslateApi(dio);

      expect(
        () => api.translate(text: '안녕', targetLanguage: 'en'),
        throwsA(isA<DioException>()),
      );
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/translate_api_test.dart
```

기대: 컴파일 실패 — `app/core/network/translate_api.dart`를 찾을 수 없음.

- [ ] **Step 3: 구현**

`app/lib/core/network/translate_api.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class TranslationResult {
  const TranslationResult({required this.translatedText, this.detectedSourceLanguage});

  final String translatedText;
  final String? detectedSourceLanguage;

  factory TranslationResult.fromJson(Map<String, dynamic> json) =>
      TranslationResult(
        translatedText: json['translatedText'] as String,
        detectedSourceLanguage: json['detectedSourceLanguage'] as String?,
      );
}

/// 서버 번역 프록시(`POST /api/translate`, Plan A)를 소비한다.
/// 번역 엔진(NMT/LLM)이 서버에서 바뀌어도 이 인터페이스는 바뀌지 않는다 (스펙 §4).
class TranslateApi {
  TranslateApi(this._dio);

  final Dio _dio;

  Future<TranslationResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/translate',
      data: {
        'text': text,
        'targetLanguage': targetLanguage,
        if (sourceLanguage != null) 'sourceLanguage': sourceLanguage,
      },
    );
    return TranslationResult.fromJson(response.data!);
  }
}

final translateApiProvider = Provider<TranslateApi>((ref) {
  return TranslateApi(ref.watch(apiClientProvider));
});
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/translate_api_test.dart
```

기대: 4개 테스트 모두 PASS.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/core/network/translate_api.dart app/test/translate_api_test.dart
git commit -m "feat(app): 번역 프록시 API 클라이언트"
```

---

### Task 4: 텍스트 번역 화면 + 프리셋 연동 (M3 게이트 대상)

**Files:**
- Create: `app/lib/features/translate/text/text_translate_controller.dart`
- Create: `app/lib/features/translate/text/text_translate_tab.dart`
- Modify: `app/lib/features/translate/translate_page.dart`
- Test: `app/test/translate/text_translate_controller_test.dart`

**Interfaces:**
- Consumes: Task 1의 `targetLanguageProvider`/`kSupportedLanguages`, Task 2의 `kPhrasePresets`, Task 3의 `translateApiProvider`
- Produces:
  - `sealed class TextTranslateState` — `Idle`, `Loading`, `Success(TranslationResult result, String sourceText)`, `Failure(String message)` 네 하위 타입
  - `class TextTranslateController extends StateNotifier<TextTranslateState>` — `Future<void> translate(String sourceText)`
  - `textTranslateControllerProvider` — `StateNotifierProvider<TextTranslateController, TextTranslateState>`
  - `TextTranslateTab` 위젯 — Task 5(OCR)와 Task 6(음성)이 각자 탭에서 같은 `textTranslateControllerProvider` 패턴을 재사용한다(상태 4종 이름을 그대로 따른다)

- [ ] **Step 1: 실패하는 컨트롤러 테스트 작성**

로직(요청 상태 전이)과 렌더링을 분리해 컨트롤러부터 순수 Dart로 테스트한다.

`app/test/translate/text_translate_controller_test.dart`:

```dart
import 'package:app/core/network/translate_api.dart';
import 'package:app/features/translate/text/text_translate_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTranslateApi implements TranslateApi {
  _FakeTranslateApi({this.result, this.error});

  final TranslationResult? result;
  final Object? error;
  String? lastText;
  String? lastTargetLanguage;

  @override
  Future<TranslationResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    lastText = text;
    lastTargetLanguage = targetLanguage;
    if (error != null) throw error!;
    return result!;
  }
}

void main() {
  group('TextTranslateController', () {
    test('초기 상태는 Idle이다', () {
      final controller = TextTranslateController(
        api: _FakeTranslateApi(result: const TranslationResult(translatedText: '')),
        targetLanguageCode: () => 'en',
      );
      expect(controller.state, isA<TextTranslateIdle>());
    });

    test('성공하면 Success 상태로 번역 결과를 담는다', () async {
      final fakeApi = _FakeTranslateApi(
        result: const TranslationResult(translatedText: 'Hello'),
      );
      final controller = TextTranslateController(
        api: fakeApi,
        targetLanguageCode: () => 'en',
      );

      await controller.translate('안녕하세요');

      final state = controller.state;
      expect(state, isA<TextTranslateSuccess>());
      state as TextTranslateSuccess;
      expect(state.result.translatedText, 'Hello');
      expect(state.sourceText, '안녕하세요');
      expect(fakeApi.lastText, '안녕하세요');
      expect(fakeApi.lastTargetLanguage, 'en');
    });

    test('빈 문자열이면 API를 호출하지 않고 Idle을 유지한다', () async {
      final fakeApi = _FakeTranslateApi(
        result: const TranslationResult(translatedText: 'unused'),
      );
      final controller = TextTranslateController(
        api: fakeApi,
        targetLanguageCode: () => 'en',
      );

      await controller.translate('   ');

      expect(controller.state, isA<TextTranslateIdle>());
      expect(fakeApi.lastText, isNull);
    });

    test('실패하면 Failure 상태가 된다', () async {
      final fakeApi = _FakeTranslateApi(error: Exception('network down'));
      final controller = TextTranslateController(
        api: fakeApi,
        targetLanguageCode: () => 'en',
      );

      await controller.translate('안녕');

      expect(controller.state, isA<TextTranslateFailure>());
    });

    test('호출 중에는 Loading 상태를 거친다', () async {
      final fakeApi = _FakeTranslateApi(
        result: const TranslationResult(translatedText: 'Hi'),
      );
      final controller = TextTranslateController(
        api: fakeApi,
        targetLanguageCode: () => 'en',
      );

      final future = controller.translate('안녕');
      expect(controller.state, isA<TextTranslateLoading>());
      await future;
      expect(controller.state, isA<TextTranslateSuccess>());
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/translate/text_translate_controller_test.dart
```

기대: 컴파일 실패 — `text_translate_controller.dart`를 찾을 수 없음.

- [ ] **Step 3: 컨트롤러 구현**

`app/lib/features/translate/text/text_translate_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/translate_api.dart';
import '../language/target_language.dart';

sealed class TextTranslateState {
  const TextTranslateState();
}

class TextTranslateIdle extends TextTranslateState {
  const TextTranslateIdle();
}

class TextTranslateLoading extends TextTranslateState {
  const TextTranslateLoading();
}

class TextTranslateSuccess extends TextTranslateState {
  const TextTranslateSuccess({required this.result, required this.sourceText});

  final TranslationResult result;
  final String sourceText;
}

class TextTranslateFailure extends TextTranslateState {
  const TextTranslateFailure(this.message);

  final String message;
}

/// `targetLanguageCode`를 콜백으로 받는 이유는 컨트롤러가 Riverpod의
/// ref 없이도(즉 위젯/프로바이더 없이) 단위 테스트되도록 하기 위해서다.
class TextTranslateController extends StateNotifier<TextTranslateState> {
  TextTranslateController({
    required TranslateApi api,
    required String Function() targetLanguageCode,
  })  : _api = api,
        _targetLanguageCode = targetLanguageCode,
        super(const TextTranslateIdle());

  final TranslateApi _api;
  final String Function() _targetLanguageCode;

  Future<void> translate(String sourceText) async {
    final trimmed = sourceText.trim();
    if (trimmed.isEmpty) {
      state = const TextTranslateIdle();
      return;
    }

    state = const TextTranslateLoading();
    try {
      final result = await _api.translate(
        text: trimmed,
        targetLanguage: _targetLanguageCode(),
      );
      state = TextTranslateSuccess(result: result, sourceText: trimmed);
    } catch (e) {
      state = TextTranslateFailure('번역에 실패했습니다: $e');
    }
  }
}

final textTranslateControllerProvider =
    StateNotifierProvider<TextTranslateController, TextTranslateState>((ref) {
  return TextTranslateController(
    api: ref.watch(translateApiProvider),
    targetLanguageCode: () => ref.read(targetLanguageProvider).code,
  );
});
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/translate/text_translate_controller_test.dart
```

기대: 5개 테스트 모두 PASS.

- [ ] **Step 5: 텍스트 번역 탭 UI 작성**

`app/lib/features/translate/text/text_translate_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../language/target_language.dart';
import '../presets/phrase_presets.dart';
import 'text_translate_controller.dart';

class TextTranslateTab extends ConsumerStatefulWidget {
  const TextTranslateTab({super.key});

  @override
  ConsumerState<TextTranslateTab> createState() => _TextTranslateTabState();
}

class _TextTranslateTabState extends ConsumerState<TextTranslateTab> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _translate() {
    ref.read(textTranslateControllerProvider.notifier).translate(_controller.text);
  }

  void _usePreset(PhrasePreset preset) {
    _controller.text = preset.textKo;
    _translate();
  }

  @override
  Widget build(BuildContext context) {
    final target = ref.watch(targetLanguageProvider);
    final state = ref.watch(textTranslateControllerProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<LanguageOption>(
            initialValue: target,
            decoration: const InputDecoration(labelText: '대상 언어'),
            items: [
              for (final option in kSupportedLanguages)
                DropdownMenuItem(value: option, child: Text(option.labelKo)),
            ],
            onChanged: (value) {
              if (value != null) {
                ref.read(targetLanguageProvider.notifier).setManually(value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '한국어로 입력',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _translate, child: const Text('번역하기')),
          const SizedBox(height: 16),
          _buildResult(state),
          const SizedBox(height: 16),
          const Text('상황별 문구', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(child: _buildPresetList()),
        ],
      ),
    );
  }

  Widget _buildResult(TextTranslateState state) {
    return switch (state) {
      TextTranslateIdle() => const SizedBox.shrink(),
      TextTranslateLoading() => const Center(child: CircularProgressIndicator()),
      TextTranslateSuccess(:final result) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(result.translatedText, style: const TextStyle(fontSize: 18)),
          ),
        ),
      TextTranslateFailure(:final message) =>
        Text(message, style: const TextStyle(color: Colors.red)),
    };
  }

  Widget _buildPresetList() {
    return ListView(
      children: [
        for (final category in PresetCategory.values) ...[
          Text(category.labelKo, style: const TextStyle(fontWeight: FontWeight.w600)),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final preset in kPhrasePresets.where((p) => p.category == category))
                ActionChip(
                  label: Text(preset.textKo),
                  onPressed: () => _usePreset(preset),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
```

- [ ] **Step 6: `TranslatePage`를 3탭 셸로 교체**

`app/lib/features/translate/translate_page.dart` 전체를 아래로 교체한다. 카메라·음성 탭은 Task 5·6에서 채운다 — 지금은 "준비 중" 자리표시자를 둔다(이 자리표시자는 Task 5·6이 즉시 지운다).

```dart
import 'package:flutter/material.dart';

import 'text/text_translate_tab.dart';

class TranslatePage extends StatelessWidget {
  const TranslatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.translate), text: '텍스트'),
              Tab(icon: Icon(Icons.camera_alt_outlined), text: '카메라'),
              Tab(icon: Icon(Icons.mic_none), text: '음성'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                TextTranslateTab(),
                Center(child: Text('카메라 번역 준비 중')),
                Center(child: Text('음성 번역 준비 중')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: 전체 검사 실행**

```bash
cd app && flutter analyze && flutter test
```

기대: analyze 무경고, 테스트 전부 PASS.

- [ ] **Step 8: 실기기/에뮬레이터로 확인 — M3 게이트 대상**

서버(`cd server && ./gradlew bootRun`, Plan A의 `/api/translate`가 아직 없다면 임시로 200 고정 응답을 주는 컨트롤러를 잠깐 붙여서라도 확인)와 앱을 함께 띄운다.

```bash
cd app && flutter run
```

확인 항목:
1. 번역 탭 → 텍스트 서브탭에서 대상 언어 드롭다운이 뜬다
2. 문구 칩을 누르면 입력창이 채워지고 자동으로 번역이 실행된다
3. 직접 입력 후 "번역하기"를 누르면 결과 카드가 뜬다

- [ ] **Step 9: 커밋**

```bash
git add app/lib/features/translate app/test/translate
git commit -m "feat(app): 텍스트 번역 화면과 상황별 문구 프리셋 연동"
```

---

### Task 5: 카메라 OCR 번역

**Files:**
- Create: `app/lib/features/translate/ocr/text_recognizer_service.dart`
- Create: `app/lib/features/translate/ocr/ocr_translate_tab.dart`
- Modify: `app/lib/features/translate/translate_page.dart`
- Modify: `app/pubspec.yaml`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Test: `app/test/translate/ocr_orchestration_test.dart`

**Interfaces:**
- Consumes: Task 3의 `translateApiProvider`, Task 1의 `targetLanguageProvider`
- Produces:
  - `abstract class TextRecognizerService { Future<String> recognizeText(String imagePath); }`
  - `class MlkitTextRecognizerService implements TextRecognizerService` — `google_mlkit_text_recognition` 사용
  - `class OcrTranslateOrchestrator` — 사진 경로를 받아 "인식 → 번역"을 순서대로 수행하고 결과(`String recognizedText, TranslationResult translation`) 또는 오류를 돌려준다. 화면은 이 클래스만 안다
  - `OcrTranslateTab` 위젯

> **스코프 결정**: 실시간 카메라 프리뷰에 인식된 텍스트를 프레임마다 겹쳐 그리는 AR형 오버레이는 만들지 않는다. 대신 `image_picker`로 사진을 한 장 찍고, 그 사진에 ML Kit을 돌려 인식된 원문과 번역문을 사진 아래에 나란히 보여주는 "오버레이 결과 화면" 방식을 쓴다. 스펙 §6-⑤의 "카메라 OCR 번역 → 텍스트 추출 → 번역 → 결과 오버레이" 요구를 만족하면서, 실시간 프레임 처리보다 훨씬 적은 상태관리로 끝난다 — R4가 처음 다루는 카메라 기능이라는 점(스펙 §8)을 고려한 절충이다.

- [ ] **Step 1: 의존성 추가**

```bash
cd app
flutter pub add google_mlkit_text_recognition image_picker permission_handler
```

- [ ] **Step 2: 실패하는 오케스트레이션 테스트 작성**

ML Kit은 네이티브 바이너리가 필요해 순수 Dart 테스트로 돌릴 수 없으므로, `TextRecognizerService`를 가짜로 대체해 "인식 결과를 받아 번역까지 잇는" 로직만 테스트한다.

`app/test/translate/ocr_orchestration_test.dart`:

```dart
import 'package:app/core/network/translate_api.dart';
import 'package:app/features/translate/ocr/text_recognizer_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTextRecognizerService implements TextRecognizerService {
  _FakeTextRecognizerService(this.textToReturn);

  final String textToReturn;

  @override
  Future<String> recognizeText(String imagePath) async => textToReturn;
}

class _FakeTranslateApi implements TranslateApi {
  _FakeTranslateApi(this.result);

  final TranslationResult result;
  String? lastText;

  @override
  Future<TranslationResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    lastText = text;
    return result;
  }
}

void main() {
  group('OcrTranslateOrchestrator', () {
    test('인식된 텍스트를 그대로 번역 API에 넘긴다', () async {
      final recognizer = _FakeTextRecognizerService('Menu: Pho 50000');
      final api = _FakeTranslateApi(const TranslationResult(translatedText: '메뉴: 쌀국수 50000'));
      final orchestrator = OcrTranslateOrchestrator(
        recognizer: recognizer,
        api: api,
        targetLanguageCode: () => 'ko',
      );

      final outcome = await orchestrator.process('/tmp/photo.jpg');

      expect(outcome.recognizedText, 'Menu: Pho 50000');
      expect(outcome.translation.translatedText, '메뉴: 쌀국수 50000');
      expect(api.lastText, 'Menu: Pho 50000');
    });

    test('인식된 텍스트가 없으면 번역을 호출하지 않고 예외를 던진다', () async {
      final recognizer = _FakeTextRecognizerService('   ');
      final api = _FakeTranslateApi(const TranslationResult(translatedText: 'unused'));
      final orchestrator = OcrTranslateOrchestrator(
        recognizer: recognizer,
        api: api,
        targetLanguageCode: () => 'ko',
      );

      expect(
        () => orchestrator.process('/tmp/photo.jpg'),
        throwsA(isA<NoTextRecognizedException>()),
      );
      expect(api.lastText, isNull);
    });
  });
}
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd app && flutter test test/translate/ocr_orchestration_test.dart
```

기대: 컴파일 실패 — `text_recognizer_service.dart`를 찾을 수 없음.

- [ ] **Step 4: 인터페이스·오케스트레이터·ML Kit 구현체 작성**

`app/lib/features/translate/ocr/text_recognizer_service.dart`:

```dart
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/network/translate_api.dart';

abstract class TextRecognizerService {
  Future<String> recognizeText(String imagePath);
}

/// google_mlkit_text_recognition은 온디바이스로 동작하며 추가 과금이 없다 (스펙 §4, §6-⑤).
class MlkitTextRecognizerService implements TextRecognizerService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<String> recognizeText(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(inputImage);
    return result.text;
  }

  void dispose() => _recognizer.close();
}

class NoTextRecognizedException implements Exception {
  @override
  String toString() => '사진에서 텍스트를 찾지 못했습니다';
}

class OcrOutcome {
  const OcrOutcome({required this.recognizedText, required this.translation});

  final String recognizedText;
  final TranslationResult translation;
}

/// "사진 경로 → 인식 → 번역"을 순서대로 수행한다. 화면은 이 클래스만 알면 되고,
/// ML Kit·dio를 직접 다루지 않는다.
class OcrTranslateOrchestrator {
  OcrTranslateOrchestrator({
    required TextRecognizerService recognizer,
    required TranslateApi api,
    required String Function() targetLanguageCode,
  })  : _recognizer = recognizer,
        _api = api,
        _targetLanguageCode = targetLanguageCode;

  final TextRecognizerService _recognizer;
  final TranslateApi _api;
  final String Function() _targetLanguageCode;

  Future<OcrOutcome> process(String imagePath) async {
    final recognizedText = (await _recognizer.recognizeText(imagePath)).trim();
    if (recognizedText.isEmpty) {
      throw NoTextRecognizedException();
    }
    final translation = await _api.translate(
      text: recognizedText,
      targetLanguage: _targetLanguageCode(),
    );
    return OcrOutcome(recognizedText: recognizedText, translation: translation);
  }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd app && flutter test test/translate/ocr_orchestration_test.dart
```

기대: 2개 테스트 모두 PASS.

- [ ] **Step 6: Android 권한 선언**

`app/android/app/src/main/AndroidManifest.xml`의 `<manifest>` 태그 바로 안, `<application>` 태그 앞에 추가한다.

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

- [ ] **Step 7: OCR 탭 UI 작성**

`app/lib/features/translate/ocr/ocr_translate_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/network/translate_api.dart';
import '../language/target_language.dart';
import 'text_recognizer_service.dart';

final _textRecognizerServiceProvider = Provider<TextRecognizerService>((ref) {
  final service = MlkitTextRecognizerService();
  ref.onDispose(service.dispose);
  return service;
});

final _ocrOrchestratorProvider = Provider<OcrTranslateOrchestrator>((ref) {
  return OcrTranslateOrchestrator(
    recognizer: ref.watch(_textRecognizerServiceProvider),
    api: ref.watch(translateApiProvider),
    targetLanguageCode: () => ref.read(targetLanguageProvider).code,
  );
});

class OcrTranslateTab extends ConsumerStatefulWidget {
  const OcrTranslateTab({super.key});

  @override
  ConsumerState<OcrTranslateTab> createState() => _OcrTranslateTabState();
}

class _OcrTranslateTabState extends ConsumerState<OcrTranslateTab> {
  bool _loading = false;
  String? _error;
  OcrOutcome? _outcome;

  Future<void> _takePhotoAndTranslate() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _error = '카메라 권한이 필요합니다.');
      return;
    }

    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _outcome = null;
    });

    try {
      final outcome = await ref.read(_ocrOrchestratorProvider).process(picked.path);
      setState(() => _outcome = outcome);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _loading ? null : _takePhotoAndTranslate,
            icon: const Icon(Icons.camera_alt),
            label: const Text('메뉴판 촬영해서 번역'),
          ),
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_outcome != null) ...[
            const Text('인식된 원문', style: TextStyle(fontWeight: FontWeight.bold)),
            Card(child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_outcome!.recognizedText),
            )),
            const SizedBox(height: 12),
            const Text('번역 결과', style: TextStyle(fontWeight: FontWeight.bold)),
            Card(child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_outcome!.translation.translatedText,
                  style: const TextStyle(fontSize: 18)),
            )),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 8: `TranslatePage`의 카메라 탭 자리표시자를 교체**

`app/lib/features/translate/translate_page.dart`에서 import를 추가하고 카메라 탭 자리표시자를 교체한다.

```dart
import 'ocr/ocr_translate_tab.dart';
```

```dart
Center(child: Text('카메라 번역 준비 중')),
```
을
```dart
const OcrTranslateTab(),
```
로 바꾼다.

- [ ] **Step 9: 전체 검사 실행**

```bash
cd app && flutter analyze && flutter test
```

기대: analyze 무경고, 테스트 전부 PASS.

- [ ] **Step 10: 실기기로 확인**

에뮬레이터는 카메라가 제한적이므로 **실기기 권장**.

```bash
cd app && flutter run
```

확인 항목:
1. 번역 탭 → 카메라 서브탭에서 버튼을 누르면 권한 요청 뒤 카메라 앱이 뜬다
2. 문구가 있는 사진(메뉴판, 표지판 등)을 찍으면 인식된 원문과 번역 결과가 순서대로 표시된다
3. 텍스트가 없는 사진을 찍으면 "텍스트를 찾지 못했습니다" 오류가 뜬다

- [ ] **Step 11: 커밋**

```bash
git add app/lib/features/translate app/test/translate app/pubspec.yaml app/pubspec.lock app/android
git commit -m "feat(app): 카메라 OCR 번역"
```

---

### Task 6: 음성 번역 (양방향 대화 모드)

**Files:**
- Create: `app/lib/features/translate/voice/speech_services.dart`
- Create: `app/lib/features/translate/voice/voice_translate_tab.dart`
- Modify: `app/lib/features/translate/translate_page.dart`
- Modify: `app/pubspec.yaml`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Test: `app/test/translate/voice_orchestration_test.dart`

**Interfaces:**
- Consumes: Task 3의 `translateApiProvider`, Task 1의 `kSupportedLanguages`
- Produces:
  - `abstract class SpeechRecognitionService { Future<bool> initialize(); Future<String?> listenOnce({required String localeId}); }`
  - `abstract class TextToSpeechService { Future<void> speak(String text, {required String localeId}); }`
  - `class DeviceSpeechRecognitionService implements SpeechRecognitionService` — `speech_to_text`
  - `class DeviceTextToSpeechService implements TextToSpeechService` — `flutter_tts`
  - `class VoiceTurnOrchestrator` — 한 사람의 발화 하나를 "듣기 → 번역 → 상대 언어로 읽어주기"로 완결하는 단위(`VoiceTurnResult recognizedText, translatedText`)
  - `VoiceTranslateTab` 위젯 — 대화 상대 A(한국어 화자)/B(현지어 화자) 두 슬롯을 토글하는 양방향 대화 모드

> **양방향 대화 모드에 대해**: "두 사람이 번갈아 말한다"는 요구(스펙 §6-⑤)를 상태 기계로 최소화한다. 화면에는 "내 차례(한국어 → 대상 언어로 읽어줌)"와 "상대 차례(대상 언어 → 한국어로 읽어줌)" 버튼 2개만 두고, 어느 버튼을 눌렀는지가 `VoiceTurnOrchestrator`에 넘길 원본/대상 언어 방향을 정한다. 대화 이력은 세션 동안만 화면 리스트에 쌓고 저장하지 않는다(경비 지갑과 달리 여기엔 영속화 요구가 스펙에 없다).

- [ ] **Step 1: 의존성 추가**

```bash
cd app
flutter pub add speech_to_text flutter_tts
```

- [ ] **Step 2: 실패하는 오케스트레이션 테스트 작성**

`speech_to_text`/`flutter_tts`도 네이티브 마이크·스피커가 필요해 순수 Dart 테스트가 불가능하므로, Task 5와 같은 방식으로 인터페이스를 가짜로 대체해 "듣기 → 번역 → 읽기" 순서와 방향 전환 로직만 검증한다.

`app/test/translate/voice_orchestration_test.dart`:

```dart
import 'package:app/core/network/translate_api.dart';
import 'package:app/features/translate/voice/speech_services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSpeechRecognitionService implements SpeechRecognitionService {
  _FakeSpeechRecognitionService(this.textToReturn);

  final String? textToReturn;
  String? lastLocaleId;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<String?> listenOnce({required String localeId}) async {
    lastLocaleId = localeId;
    return textToReturn;
  }
}

class _FakeTextToSpeechService implements TextToSpeechService {
  String? spokenText;
  String? spokenLocale;

  @override
  Future<void> speak(String text, {required String localeId}) async {
    spokenText = text;
    spokenLocale = localeId;
  }
}

class _FakeTranslateApi implements TranslateApi {
  _FakeTranslateApi(this.result);

  final TranslationResult result;
  String? lastText;
  String? lastTarget;

  @override
  Future<TranslationResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    lastText = text;
    lastTarget = targetLanguage;
    return result;
  }
}

void main() {
  group('VoiceTurnOrchestrator', () {
    test('인식한 말을 번역하고 대상 언어로 읽어준다', () async {
      final speech = _FakeSpeechRecognitionService('안녕하세요');
      final tts = _FakeTextToSpeechService();
      final api = _FakeTranslateApi(const TranslationResult(translatedText: 'Hello'));
      final orchestrator = VoiceTurnOrchestrator(speech: speech, tts: tts, api: api);

      final result = await orchestrator.runTurn(
        sourceLocaleId: 'ko-KR',
        targetLanguageCode: 'en',
        targetLocaleId: 'en-US',
      );

      expect(result.recognizedText, '안녕하세요');
      expect(result.translatedText, 'Hello');
      expect(speech.lastLocaleId, 'ko-KR');
      expect(api.lastText, '안녕하세요');
      expect(api.lastTarget, 'en');
      expect(tts.spokenText, 'Hello');
      expect(tts.spokenLocale, 'en-US');
    });

    test('아무 말도 인식하지 못하면 null을 반환하고 번역·TTS를 호출하지 않는다', () async {
      final speech = _FakeSpeechRecognitionService(null);
      final tts = _FakeTextToSpeechService();
      final api = _FakeTranslateApi(const TranslationResult(translatedText: 'unused'));
      final orchestrator = VoiceTurnOrchestrator(speech: speech, tts: tts, api: api);

      final result = await orchestrator.runTurn(
        sourceLocaleId: 'ko-KR',
        targetLanguageCode: 'en',
        targetLocaleId: 'en-US',
      );

      expect(result, isNull);
      expect(api.lastText, isNull);
      expect(tts.spokenText, isNull);
    });
  });
}
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd app && flutter test test/translate/voice_orchestration_test.dart
```

기대: 컴파일 실패 — `speech_services.dart`를 찾을 수 없음.

- [ ] **Step 4: 인터페이스·오케스트레이터·기기 구현체 작성**

`app/lib/features/translate/voice/speech_services.dart`:

```dart
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/network/translate_api.dart';

abstract class SpeechRecognitionService {
  Future<bool> initialize();

  /// 한 번 듣고 인식된 문장을 반환한다. 아무 말도 인식하지 못하면 null.
  Future<String?> listenOnce({required String localeId});
}

abstract class TextToSpeechService {
  Future<void> speak(String text, {required String localeId});
}

/// speech_to_text는 온디바이스로 동작하며 추가 과금이 없다 (스펙 §4, §6-⑤).
class DeviceSpeechRecognitionService implements SpeechRecognitionService {
  final _speech = stt.SpeechToText();

  @override
  Future<bool> initialize() => _speech.initialize();

  @override
  Future<String?> listenOnce({required String localeId}) {
    final completer = Completer<String?>();
    _speech.listen(
      localeId: localeId,
      onResult: (result) {
        if (result.finalResult) {
          completer.complete(
            result.recognizedWords.isEmpty ? null : result.recognizedWords,
          );
        }
      },
    );
    return completer.future;
  }
}

/// flutter_tts도 온디바이스로 동작하며 추가 과금이 없다.
class DeviceTextToSpeechService implements TextToSpeechService {
  final _tts = FlutterTts();

  @override
  Future<void> speak(String text, {required String localeId}) async {
    await _tts.setLanguage(localeId);
    await _tts.speak(text);
  }
}

class VoiceTurnResult {
  const VoiceTurnResult({required this.recognizedText, required this.translatedText});

  final String recognizedText;
  final String translatedText;
}

/// 한 사람의 발화 하나를 "듣기 → 번역 → 상대 언어로 읽어주기"로 완결한다.
/// 양방향 대화 모드는 이 클래스를 방향만 바꿔 두 번 호출하는 방식으로 구현된다.
class VoiceTurnOrchestrator {
  VoiceTurnOrchestrator({
    required SpeechRecognitionService speech,
    required TextToSpeechService tts,
    required TranslateApi api,
  })  : _speech = speech,
        _tts = tts,
        _api = api;

  final SpeechRecognitionService _speech;
  final TextToSpeechService _tts;
  final TranslateApi _api;

  Future<VoiceTurnResult?> runTurn({
    required String sourceLocaleId,
    required String targetLanguageCode,
    required String targetLocaleId,
  }) async {
    final recognized = await _speech.listenOnce(localeId: sourceLocaleId);
    if (recognized == null || recognized.trim().isEmpty) {
      return null;
    }

    final translation = await _api.translate(
      text: recognized,
      targetLanguage: targetLanguageCode,
    );

    await _tts.speak(translation.translatedText, localeId: targetLocaleId);

    return VoiceTurnResult(
      recognizedText: recognized,
      translatedText: translation.translatedText,
    );
  }
}
```

`dart:async`의 `Completer`를 쓰므로 파일 상단에 import를 추가한다.

```dart
import 'dart:async';
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd app && flutter test test/translate/voice_orchestration_test.dart
```

기대: 2개 테스트 모두 PASS.

- [ ] **Step 6: Android 권한 선언**

`app/android/app/src/main/AndroidManifest.xml`에 Task 5에서 추가한 카메라 권한 아래에 추가한다.

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

- [ ] **Step 7: 음성 탭 UI 작성 — 양방향 대화 모드**

`app/lib/features/translate/voice/voice_translate_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/network/translate_api.dart';
import '../language/target_language.dart';
import 'speech_services.dart';

final _speechServiceProvider =
    Provider<SpeechRecognitionService>((ref) => DeviceSpeechRecognitionService());
final _ttsServiceProvider = Provider<TextToSpeechService>((ref) => DeviceTextToSpeechService());

final _voiceOrchestratorProvider = Provider<VoiceTurnOrchestrator>((ref) {
  return VoiceTurnOrchestrator(
    speech: ref.watch(_speechServiceProvider),
    tts: ref.watch(_ttsServiceProvider),
    api: ref.watch(translateApiProvider),
  );
});

/// BCP-47 언어 코드 → 음성 엔진용 로케일 ID. speech_to_text/flutter_tts는
/// `ko`가 아니라 `ko-KR` 형태의 로케일을 요구한다.
const Map<String, String> _localeIdByLanguageCode = {
  'ko': 'ko-KR', 'en': 'en-US', 'ja': 'ja-JP', 'vi': 'vi-VN', 'th': 'th-TH',
  'zh-CN': 'zh-CN', 'zh-TW': 'zh-TW', 'fr': 'fr-FR', 'it': 'it-IT', 'es': 'es-ES',
  'de': 'de-DE', 'tr': 'tr-TR', 'cs': 'cs-CZ', 'id': 'id-ID',
};

enum _Speaker { me, counterpart }

class _ConversationEntry {
  const _ConversationEntry({required this.speaker, required this.original, required this.translated});

  final _Speaker speaker;
  final String original;
  final String translated;
}

class VoiceTranslateTab extends ConsumerStatefulWidget {
  const VoiceTranslateTab({super.key});

  @override
  ConsumerState<VoiceTranslateTab> createState() => _VoiceTranslateTabState();
}

class _VoiceTranslateTabState extends ConsumerState<VoiceTranslateTab> {
  final _history = <_ConversationEntry>[];
  bool _listening = false;
  String? _error;

  Future<void> _runTurn(_Speaker speaker) async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() => _error = '마이크 권한이 필요합니다.');
      return;
    }

    final target = ref.read(targetLanguageProvider);
    final koreanLocale = _localeIdByLanguageCode['ko']!;
    final targetLocale = _localeIdByLanguageCode[target.code] ?? 'en-US';

    setState(() {
      _listening = true;
      _error = null;
    });

    try {
      final orchestrator = ref.read(_voiceOrchestratorProvider);
      final result = await orchestrator.runTurn(
        sourceLocaleId: speaker == _Speaker.me ? koreanLocale : targetLocale,
        targetLanguageCode: speaker == _Speaker.me ? target.code : 'ko',
        targetLocaleId: speaker == _Speaker.me ? targetLocale : koreanLocale,
      );
      if (result != null) {
        setState(() {
          _history.add(_ConversationEntry(
            speaker: speaker,
            original: result.recognizedText,
            translated: result.translatedText,
          ));
        });
      }
    } catch (e) {
      setState(() => _error = '음성 번역에 실패했습니다: $e');
    } finally {
      setState(() => _listening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _history.length,
              itemBuilder: (context, i) {
                final entry = _history[i];
                final isMe = entry.speaker == _Speaker.me;
                return Align(
                  alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
                  child: Card(
                    color: isMe ? null : Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.original, style: const TextStyle(fontSize: 14)),
                          Text(entry.translated,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _listening ? null : () => _runTurn(_Speaker.me),
                  icon: const Icon(Icons.mic),
                  label: const Text('내 차례 (한국어)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _listening ? null : () => _runTurn(_Speaker.counterpart),
                  icon: const Icon(Icons.mic),
                  label: const Text('상대 차례'),
                ),
              ),
            ],
          ),
          if (_listening)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 8: `TranslatePage`의 음성 탭 자리표시자를 교체**

`app/lib/features/translate/translate_page.dart`에서 import를 추가한다.

```dart
import 'voice/voice_translate_tab.dart';
```

그리고 아래를

```dart
Center(child: Text('음성 번역 준비 중')),
```

이렇게 바꾼다.

```dart
const VoiceTranslateTab(),
```

- [ ] **Step 9: 전체 검사 실행**

```bash
cd app && flutter analyze && flutter test
```

기대: analyze 무경고, 테스트 전부 PASS.

- [ ] **Step 10: 실기기로 확인 — Plan E 전체 통합 확인**

```bash
cd app && flutter run
```

확인 항목:
1. 음성 탭에서 "내 차례" 버튼을 누르고 한국어로 말하면, 대상 언어로 번역된 텍스트가 대화 이력에 뜨고 스피커로 읽어준다
2. "상대 차례" 버튼을 누르고 대상 언어로 말하면, 한국어로 번역되어 읽어준다
3. 번역 탭의 텍스트/카메라/음성 3개 서브탭이 모두 동작한다 (스펙 §6-⑤ 전체)
4. 목적지 국가가 바뀌는 시나리오가 아직 없으므로(Plan B 미완성), 대상 언어 드롭다운(텍스트 탭)으로 수동 전환해 각 언어에서 3종이 정상 동작하는지 확인한다

- [ ] **Step 11: 커밋과 PR**

```bash
git add app/lib/features/translate app/test/translate app/pubspec.yaml app/pubspec.lock app/android
git commit -m "feat(app): 음성 번역과 양방향 대화 모드"
git push origin HEAD
```

`develop`으로 PR을 올리고 2인 승인을 받는다. CI의 `Flutter` job이 초록인지 확인한다.

---

## Plan E 완료 체크리스트

- [ ] 목적지 국가가 정해지면(Plan B 연동 시) 대상 언어가 자동으로 바뀐다 — Task 1의 `setFromCountry` 진입점이 준비되어 있다
- [ ] 텍스트를 입력하거나 프리셋 칩을 누르면 번역 결과가 뜬다
- [ ] 입국심사/식당/교통/응급 4개 카테고리에 각각 4개 이상의 문구가 있다
- [ ] 카메라로 찍은 사진에서 텍스트를 인식해 번역 결과를 보여준다
- [ ] 음성으로 말하면 번역되어 소리로 읽어주고, 양방향(내 차례/상대 차례)이 모두 동작한다
- [ ] OCR·STT·TTS 어디에도 Google Cloud API 키가 앱에 박혀 있지 않다 — 번역 텍스트만 서버 프록시를 거친다
- [ ] `app/test/` 전체가 `flutter test`로 PASS한다 (`flutter analyze` 무경고)

---

## Self-Review 메모

- **스펙 커버리지**: §6-⑤의 4개 요구(목적지 언어 자동 설정, 텍스트+프리셋, 카메라 OCR, 음성+양방향)를 각각 Task 1, Task 2+4, Task 5, Task 6이 담당한다. "온디바이스라 추가 비용 없음"은 Task 5·6의 서비스 구현체 주석과 Global Constraints에 명시했다.
- **타입 일관성**: `TranslationResult`(Task 3) → `TextTranslateSuccess.result`(Task 4) → `OcrOutcome.translation`(Task 5) → `VoiceTurnResult.translatedText`(Task 6)까지 동일한 모델을 재사용한다. `targetLanguageProvider`(Task 1)는 Task 4·5·6이 모두 같은 이름으로 참조한다.
- **플레이스홀더 검사**: "준비 중" 텍스트는 Task 4에서 잠깐 등장하지만 같은 계획서의 Task 5·6에서 즉시 교체되는 것으로 명시했다 — 계획서가 끝난 시점에는 남아 있지 않는다.
