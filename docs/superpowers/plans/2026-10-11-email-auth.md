# 이메일 회원가입·로그인 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Firebase 이메일/비밀번호 회원가입·로그인·비밀번호 재설정 화면과 로그아웃(계정 시트)을 추가한다.

**Architecture:** `AuthRepository`에 이메일 메서드와 `currentUser`를 더하고, Firebase 오류를 `AuthException(AuthErrorCode)`로 통일한다. 로그인 화면은 `authRepositoryProvider`를 직접 쓰고, 라우터는 로그아웃 상태에서 `/login/*`만 허용한다. 서버는 바뀌지 않는다.

**Tech Stack:** Flutter, Riverpod 3, go_router, firebase_auth 6, google_sign_in 6

**Spec:** `docs/superpowers/specs/2026-10-11-email-auth-design.md`

## Global Constraints

- 브랜치 `email-login`. 커밋에 `Co-Authored-By`·Claude·AI 트레일러 금지.
- 서버 코드·`pubspec.yaml` 변경 금지.
- 앱 명령은 `app/`에서. 정적 분석은 `dart analyze`(flutter analyze는 이 PC에서 죽는다).
- 경로: `/login`, `/login/signup`, `/login/reset`.
- 닉네임 1~20자(앞뒤 공백 제거 후), 비밀번호 6자 이상.
- 문구는 스펙 §3.5·§3.6 표의 문자열을 그대로 쓴다.

---

## File Structure

- Create `app/lib/core/auth/auth_exception.dart` — `AuthErrorCode`, `AuthException`, `mapFirebaseAuthCode`, `authErrorMessage`
- Modify `app/lib/core/auth/auth_repository.dart`, `firebase_auth_repository.dart`, `dev_auth_repository.dart`
- Modify `app/test/auth/fake_auth_repository.dart`, `app/test/auth/auth_state_test.dart`
- Create `app/lib/features/login/auth_validators.dart`, `app/lib/features/login/widgets/auth_text_field.dart`
- Modify `app/lib/features/login/login_page.dart`
- Create `app/lib/features/login/sign_up_page.dart`, `app/lib/features/login/password_reset_page.dart`
- Modify `app/lib/router.dart`, `app/lib/main.dart`, `app/lib/main_dev.dart`
- Create `app/lib/features/account/account_sheet.dart`
- Modify `app/lib/features/visa/trip_list_page.dart`

---

### Task 1: 인증 계층 — 이메일 메서드와 오류 통일

**Files:**
- Create: `app/lib/core/auth/auth_exception.dart`
- Modify: `app/lib/core/auth/auth_repository.dart`, `app/lib/core/auth/firebase_auth_repository.dart`, `app/lib/core/auth/dev_auth_repository.dart`
- Modify: `app/test/auth/fake_auth_repository.dart`
- Test: `app/test/auth/auth_exception_test.dart`, `app/test/auth/auth_state_test.dart`

**Interfaces:**
- Produces:
  - `enum AuthErrorCode { invalidCredential, emailAlreadyInUse, accountExistsWithDifferentCredential, weakPassword, invalidEmail, network, tooManyRequests, unknown }`
  - `class AuthException implements Exception { const AuthException(this.code); final AuthErrorCode code; }`
  - `AuthErrorCode mapFirebaseAuthCode(String code)`, `String authErrorMessage(AuthErrorCode code)`
  - `AuthRepository`: `AppUser? get currentUser`, `Future<AppUser> signInWithEmail({required String email, required String password})`, `Future<AppUser> signUpWithEmail({required String email, required String password, required String nickname})`, `Future<void> sendPasswordReset(String email)`
  - `FakeAuthRepository` (test): `AuthException? nextError` (다음 호출 하나가 던지고 지워짐), `bool cancelGoogle`, 호출 기록 `emailSignInCalls`(List<({String email, String password})>), `signUpCalls`(List<({String email, String password, String nickname})>), `resetCalls`(List<String>), `googleSignInCalls`(int), `signOutCalls`(int); `signIn(AppUser user)` 헬퍼(로그인 상태로 만든다)

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/auth/auth_exception_test.dart` 생성:
```dart
import 'package:app/core/auth/auth_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firebase 오류 코드를 앱 오류 코드로 바꾼다', () {
    expect(mapFirebaseAuthCode('invalid-credential'), AuthErrorCode.invalidCredential);
    expect(mapFirebaseAuthCode('wrong-password'), AuthErrorCode.invalidCredential);
    expect(mapFirebaseAuthCode('user-not-found'), AuthErrorCode.invalidCredential);
    expect(mapFirebaseAuthCode('INVALID_LOGIN_CREDENTIALS'), AuthErrorCode.invalidCredential);
    expect(mapFirebaseAuthCode('email-already-in-use'), AuthErrorCode.emailAlreadyInUse);
    expect(mapFirebaseAuthCode('account-exists-with-different-credential'),
        AuthErrorCode.accountExistsWithDifferentCredential);
    expect(mapFirebaseAuthCode('weak-password'), AuthErrorCode.weakPassword);
    expect(mapFirebaseAuthCode('invalid-email'), AuthErrorCode.invalidEmail);
    expect(mapFirebaseAuthCode('network-request-failed'), AuthErrorCode.network);
    expect(mapFirebaseAuthCode('too-many-requests'), AuthErrorCode.tooManyRequests);
    expect(mapFirebaseAuthCode('user-disabled'), AuthErrorCode.unknown);
  });

  test('앱 오류 코드마다 한국어 안내 문구가 있다', () {
    expect(authErrorMessage(AuthErrorCode.invalidCredential), '이메일 또는 비밀번호가 맞지 않습니다.');
    expect(authErrorMessage(AuthErrorCode.emailAlreadyInUse),
        '이미 가입된 이메일입니다. 이메일 또는 Google로 로그인해 주세요.');
    expect(authErrorMessage(AuthErrorCode.accountExistsWithDifferentCredential),
        '이메일로 가입된 계정입니다. 이메일로 로그인해 주세요.');
    expect(authErrorMessage(AuthErrorCode.weakPassword), '비밀번호는 6자 이상이어야 합니다.');
    expect(authErrorMessage(AuthErrorCode.invalidEmail), '이메일 형식을 확인해 주세요.');
    expect(authErrorMessage(AuthErrorCode.network), '네트워크를 확인해 주세요.');
    expect(authErrorMessage(AuthErrorCode.tooManyRequests), '잠시 후 다시 시도해 주세요.');
    expect(authErrorMessage(AuthErrorCode.unknown), '로그인하지 못했습니다. 잠시 후 다시 시도해 주세요.');
  });
}
```

`app/test/auth/auth_state_test.dart` — `group('AuthRepository 계약', ...)` 안 마지막 테스트 뒤에 추가:
```dart

    test('이메일로 가입하면 닉네임을 가진 사용자로 로그인되고 currentUser에도 보인다', () async {
      final user = await repo.signUpWithEmail(
          email: 'new@example.com', password: 'secret1', nickname: '새여행자');

      expect(user.displayName, '새여행자');
      expect(user.email, 'new@example.com');
      expect(repo.currentUser?.displayName, '새여행자');
      expect(repo.signUpCalls.single.nickname, '새여행자');
    });

    test('nextError를 지정하면 다음 호출 하나만 그 오류를 던진다', () async {
      repo.nextError = const AuthException(AuthErrorCode.invalidCredential);

      await expectLater(
        repo.signInWithEmail(email: 'a@b.com', password: 'x'),
        throwsA(isA<AuthException>()),
      );
      expect(await repo.signInWithEmail(email: 'a@b.com', password: 'x'), isA<AppUser>());
    });
```
그리고 파일 상단 import에 추가:
```dart
import 'package:app/core/auth/auth_exception.dart';
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/auth/`
Expected: FAIL — `auth_exception.dart` 없음, `signUpWithEmail` 정의 없음

- [ ] **Step 3: 구현**

`app/lib/core/auth/auth_exception.dart` 생성:
```dart
/// 로그인·가입 실패의 종류. Firebase 오류 코드를 화면이 알 필요 없게 이 값으로 바꿔 던진다.
enum AuthErrorCode {
  invalidCredential,
  emailAlreadyInUse,
  accountExistsWithDifferentCredential,
  weakPassword,
  invalidEmail,
  network,
  tooManyRequests,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.code);

  final AuthErrorCode code;

  @override
  String toString() => authErrorMessage(code);
}

/// Firebase Auth 오류 코드 → 앱 오류 코드. 모르는 코드는 [AuthErrorCode.unknown].
/// 이메일 열거 보호가 켜진 프로젝트는 틀린 비밀번호·없는 계정을 모두 invalid-credential로 준다.
AuthErrorCode mapFirebaseAuthCode(String code) => switch (code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'INVALID_LOGIN_CREDENTIALS' =>
        AuthErrorCode.invalidCredential,
      'email-already-in-use' => AuthErrorCode.emailAlreadyInUse,
      'account-exists-with-different-credential' =>
        AuthErrorCode.accountExistsWithDifferentCredential,
      'weak-password' => AuthErrorCode.weakPassword,
      'invalid-email' => AuthErrorCode.invalidEmail,
      'network-request-failed' => AuthErrorCode.network,
      'too-many-requests' => AuthErrorCode.tooManyRequests,
      _ => AuthErrorCode.unknown,
    };

/// 화면에 보여줄 안내 문구. 이미 가입된 이메일이 Google 계정인지 이메일 계정인지는 Firebase가
/// 알려주지 않으므로 두 경우를 함께 안내한다.
String authErrorMessage(AuthErrorCode code) => switch (code) {
      AuthErrorCode.invalidCredential => '이메일 또는 비밀번호가 맞지 않습니다.',
      AuthErrorCode.emailAlreadyInUse => '이미 가입된 이메일입니다. 이메일 또는 Google로 로그인해 주세요.',
      AuthErrorCode.accountExistsWithDifferentCredential => '이메일로 가입된 계정입니다. 이메일로 로그인해 주세요.',
      AuthErrorCode.weakPassword => '비밀번호는 6자 이상이어야 합니다.',
      AuthErrorCode.invalidEmail => '이메일 형식을 확인해 주세요.',
      AuthErrorCode.network => '네트워크를 확인해 주세요.',
      AuthErrorCode.tooManyRequests => '잠시 후 다시 시도해 주세요.',
      AuthErrorCode.unknown => '로그인하지 못했습니다. 잠시 후 다시 시도해 주세요.',
    };
```

`app/lib/core/auth/auth_repository.dart` 전체 교체:
```dart
import 'app_user.dart';

/// 화면은 Firebase를 직접 부르지 않고 이 인터페이스만 거친다. 실패는 [AuthException]
/// (`auth_exception.dart`)으로, 사용자가 Google 로그인을 취소하면 `AuthCancelledException`으로 던진다.
abstract class AuthRepository {
  /// 로그인 상태 변화를 방출한다. 로그아웃 상태에서는 null.
  Stream<AppUser?> authStateChanges();

  /// 지금 로그인한 사용자의 최신 프로필. 로그아웃 상태면 null.
  /// 가입 직후에는 [authStateChanges]가 닉네임 저장 전에 방출하므로, 닉네임이 필요한 화면은 이 값을 읽는다.
  AppUser? get currentUser;

  Future<AppUser> signInWithGoogle();

  Future<AppUser> signInWithEmail({required String email, required String password});

  /// 계정을 만들고 닉네임을 프로필 이름(displayName)으로 저장한다. 성공하면 로그인된 상태가 된다.
  Future<AppUser> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
  });

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();

  /// 서버 호출에 붙일 Firebase ID Token. 로그아웃 상태면 null.
  Future<String?> currentIdToken();
}
```

`app/lib/core/auth/firebase_auth_repository.dart` 전체 교체:
```dart
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import 'app_user.dart';
import 'auth_exception.dart';
import 'auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({fb.FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? fb.FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  @override
  Stream<AppUser?> authStateChanges() =>
      _auth.authStateChanges().map(_toAppUser);

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  @override
  Future<AppUser> signInWithGoogle() => _guard(() async {
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          throw AuthCancelledException();
        }
        final googleAuth = await googleUser.authentication;
        final credential = fb.GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final result = await _auth.signInWithCredential(credential);
        return _requireUser(result.user);
      });

  @override
  Future<AppUser> signInWithEmail({required String email, required String password}) =>
      _guard(() async {
        final result = await _auth.signInWithEmailAndPassword(email: email, password: password);
        return _requireUser(result.user);
      });

  @override
  Future<AppUser> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
  }) =>
      _guard(() async {
        final result =
            await _auth.createUserWithEmailAndPassword(email: email, password: password);
        final user = result.user!;
        await user.updateDisplayName(nickname);
        await user.reload();
        return _requireUser(_auth.currentUser);
      });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email));

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  @override
  Future<String?> currentIdToken() async => _auth.currentUser?.getIdToken();

  /// Firebase 오류를 화면이 아는 [AuthException]으로 바꿔 던진다. 취소(`AuthCancelledException`)는 그대로 통과한다.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(mapFirebaseAuthCode(e.code));
    }
  }

  AppUser _requireUser(fb.User? user) {
    final appUser = _toAppUser(user);
    if (appUser == null) throw const AuthException(AuthErrorCode.unknown);
    return appUser;
  }

  AppUser? _toAppUser(fb.User? user) {
    if (user == null) return null;
    return AppUser(
      uid: user.uid,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      email: user.email,
    );
  }
}

class AuthCancelledException implements Exception {
  @override
  String toString() => '로그인이 취소되었습니다';
}
```

`app/lib/core/auth/dev_auth_repository.dart` — 클래스 안 `signInWithGoogle` 메서드 아래에 추가:
```dart

  @override
  AppUser? get currentUser => _current;

  @override
  Future<AppUser> signInWithEmail({required String email, required String password}) async {
    _current = AppUser(uid: 'dev-user', displayName: '개발용 테스터', email: email);
    _controller.add(_current);
    return _current!;
  }

  @override
  Future<AppUser> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
  }) async {
    _current = AppUser(uid: 'dev-user', displayName: nickname, email: email);
    _controller.add(_current);
    return _current!;
  }

  @override
  Future<void> sendPasswordReset(String email) async {}
```

`app/test/auth/fake_auth_repository.dart` 전체 교체:
```dart
import 'dart:async';

import 'package:app/core/auth/app_user.dart';
import 'package:app/core/auth/auth_exception.dart';
import 'package:app/core/auth/auth_repository.dart';
import 'package:app/core/auth/firebase_auth_repository.dart' show AuthCancelledException;

/// 테스트용 인증 저장소. 호출을 기록하고, [nextError]를 지정하면 다음 호출 하나가 그 오류를 던진다.
class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current;
  String? _idToken;

  AuthException? nextError;
  bool cancelGoogle = false;

  int googleSignInCalls = 0;
  int signOutCalls = 0;
  final List<({String email, String password})> emailSignInCalls = [];
  final List<({String email, String password, String nickname})> signUpCalls = [];
  final List<String> resetCalls = [];

  /// 로그인된 상태로 만든다.
  void signIn(AppUser user) {
    _current = user;
    _idToken = 'valid-token';
    _controller.add(user);
  }

  void _throwIfError() {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  AppUser? get currentUser => _current;

  @override
  Future<AppUser> signInWithGoogle() async {
    googleSignInCalls++;
    if (cancelGoogle) throw AuthCancelledException();
    _throwIfError();
    signIn(const AppUser(uid: 'uid-123', displayName: '테스터', email: 't@example.com'));
    return _current!;
  }

  @override
  Future<AppUser> signInWithEmail({required String email, required String password}) async {
    emailSignInCalls.add((email: email, password: password));
    _throwIfError();
    signIn(AppUser(uid: 'uid-email', email: email));
    return _current!;
  }

  @override
  Future<AppUser> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
  }) async {
    signUpCalls.add((email: email, password: password, nickname: nickname));
    _throwIfError();
    signIn(AppUser(uid: 'uid-new', displayName: nickname, email: email));
    return _current!;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    resetCalls.add(email);
    _throwIfError();
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _current = null;
    _idToken = null;
    _controller.add(null);
  }

  @override
  Future<String?> currentIdToken() async => _idToken;

  void dispose() => _controller.close();
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/auth/ && dart analyze`
Expected: PASS, `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add app/lib/core/auth app/test/auth
git commit -m "feat(app): 인증 저장소에 이메일 가입·로그인·비밀번호 재설정 추가"
```

---

### Task 2: 로그인·회원가입·비밀번호 재설정 화면과 라우팅

**Files:**
- Create: `app/lib/features/login/auth_validators.dart`, `app/lib/features/login/widgets/auth_text_field.dart`, `app/lib/features/login/sign_up_page.dart`, `app/lib/features/login/password_reset_page.dart`
- Modify: `app/lib/features/login/login_page.dart` (전체 교체), `app/lib/router.dart`, `app/lib/main.dart`, `app/lib/main_dev.dart`
- Test: `app/test/login/auth_validators_test.dart`, `app/test/login/login_page_test.dart`, `app/test/login/sign_up_page_test.dart`, `app/test/login/password_reset_page_test.dart`, `app/test/router_test.dart`

**Interfaces:**
- Consumes: Task 1의 `AuthRepository` 메서드, `AuthException`, `AuthErrorCode`, `authErrorMessage`, `AuthCancelledException`, 테스트 `FakeAuthRepository`
- Produces: `AppRoutes.signUp = '/login/signup'`, `AppRoutes.passwordReset = '/login/reset'`; `createRouter({required bool isLoggedIn})` (`onSignIn` 제거); `LoginPage()`, `SignUpPage()`, `PasswordResetPage()`; `AuthTextField({required String label, required TextEditingController controller, Key? fieldKey, FormFieldValidator<String>? validator, bool obscureText, TextInputType? keyboardType})`; 검사 함수 `validateNickname`, `validateEmail`, `validateLoginPassword`, `validateNewPassword`, `validatePasswordConfirm`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/login/auth_validators_test.dart` 생성:
```dart
import 'package:app/features/login/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('닉네임은 공백 제외 1~20자', () {
    expect(validateNickname('  '), '닉네임을 입력해 주세요.');
    expect(validateNickname('가' * 21), '닉네임은 20자 이하로 입력해 주세요.');
    expect(validateNickname(' 여행자 '), isNull);
    expect(validateNickname('가' * 20), isNull);
  });

  test('이메일은 비어 있지 않고 형식이 맞아야 한다', () {
    expect(validateEmail(''), '이메일을 입력해 주세요.');
    expect(validateEmail('abc'), '이메일 형식을 확인해 주세요.');
    expect(validateEmail('a@b'), '이메일 형식을 확인해 주세요.');
    expect(validateEmail(' a@b.com '), isNull);
  });

  test('로그인 비밀번호는 비어 있지만 않으면 된다', () {
    expect(validateLoginPassword(''), '비밀번호를 입력해 주세요.');
    expect(validateLoginPassword('1'), isNull);
  });

  test('새 비밀번호는 6자 이상', () {
    expect(validateNewPassword(''), '비밀번호를 입력해 주세요.');
    expect(validateNewPassword('12345'), '비밀번호는 6자 이상이어야 합니다.');
    expect(validateNewPassword('123456'), isNull);
  });

  test('비밀번호 확인은 비밀번호와 같아야 한다', () {
    expect(validatePasswordConfirm('abc123', 'abc124'), '비밀번호가 일치하지 않습니다.');
    expect(validatePasswordConfirm('abc123', 'abc123'), isNull);
  });
}
```

`app/test/login/login_page_test.dart` 생성:
```dart
import 'package:app/core/auth/auth_exception.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/login/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../auth/fake_auth_repository.dart';

Future<FakeAuthRepository> _pumpLogin(WidgetTester tester) async {
  final repo = FakeAuthRepository();
  addTearDown(repo.dispose);
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/login/signup', builder: (_, _) => const Scaffold(body: Text('가입 화면'))),
      GoRoute(path: '/login/reset', builder: (_, _) => const Scaffold(body: Text('재설정 화면'))),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _fillAndSubmit(WidgetTester tester, {required String email, required String password}) async {
  await tester.enterText(find.byKey(const Key('loginEmailField')), email);
  await tester.enterText(find.byKey(const Key('loginPasswordField')), password);
  await tester.tap(find.byKey(const Key('emailLoginButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('이메일과 비밀번호로 로그인한다(이메일 앞뒤 공백은 지운다)', (tester) async {
    final repo = await _pumpLogin(tester);

    await _fillAndSubmit(tester, email: ' me@example.com ', password: 'secret1');

    expect(repo.emailSignInCalls.single, (email: 'me@example.com', password: 'secret1'));
    expect(find.byKey(const Key('authError')), findsNothing);
  });

  testWidgets('입력 검사를 통과하지 못하면 요청하지 않고 칸 아래에 안내한다', (tester) async {
    final repo = await _pumpLogin(tester);

    await _fillAndSubmit(tester, email: 'abc', password: '');

    expect(repo.emailSignInCalls, isEmpty);
    expect(find.text('이메일 형식을 확인해 주세요.'), findsOneWidget);
    expect(find.text('비밀번호를 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('이메일 또는 비밀번호가 틀리면 안내한다', (tester) async {
    final repo = await _pumpLogin(tester);
    repo.nextError = const AuthException(AuthErrorCode.invalidCredential);

    await _fillAndSubmit(tester, email: 'me@example.com', password: 'wrong');

    expect(find.text('이메일 또는 비밀번호가 맞지 않습니다.'), findsOneWidget);
  });

  testWidgets('Google 로그인 실패는 안내하고, 취소는 안내하지 않는다', (tester) async {
    final repo = await _pumpLogin(tester);

    repo.cancelGoogle = true;
    await tester.tap(find.text('Google로 계속하기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('authError')), findsNothing);

    repo
      ..cancelGoogle = false
      ..nextError = const AuthException(AuthErrorCode.accountExistsWithDifferentCredential);
    await tester.tap(find.text('Google로 계속하기'));
    await tester.pumpAndSettle();
    expect(find.text('이메일로 가입된 계정입니다. 이메일로 로그인해 주세요.'), findsOneWidget);
    expect(repo.googleSignInCalls, 2);
  });

  testWidgets('회원가입과 비밀번호 재설정 화면으로 갈 수 있다', (tester) async {
    await _pumpLogin(tester);

    await tester.ensureVisible(find.byKey(const Key('signUpLink')));
    await tester.tap(find.byKey(const Key('signUpLink')));
    await tester.pumpAndSettle();
    expect(find.text('가입 화면'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('forgotPasswordLink')));
    await tester.tap(find.byKey(const Key('forgotPasswordLink')));
    await tester.pumpAndSettle();
    expect(find.text('재설정 화면'), findsOneWidget);
  });
}
```

`app/test/login/sign_up_page_test.dart` 생성:
```dart
import 'package:app/core/auth/auth_exception.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/login/sign_up_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../auth/fake_auth_repository.dart';

Future<FakeAuthRepository> _pumpSignUp(WidgetTester tester) async {
  final repo = FakeAuthRepository();
  addTearDown(repo.dispose);
  final router = GoRouter(
    initialLocation: '/login/signup',
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const Scaffold(body: Text('로그인 화면'))),
      GoRoute(path: '/login/signup', builder: (_, _) => const SignUpPage()),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _fill(
  WidgetTester tester, {
  String nickname = '여행자',
  String email = 'new@example.com',
  String password = 'secret1',
  String? confirm,
}) async {
  await tester.enterText(find.byKey(const Key('signUpNicknameField')), nickname);
  await tester.enterText(find.byKey(const Key('signUpEmailField')), email);
  await tester.enterText(find.byKey(const Key('signUpPasswordField')), password);
  await tester.enterText(find.byKey(const Key('signUpConfirmField')), confirm ?? password);
  await tester.ensureVisible(find.byKey(const Key('signUpButton')));
  await tester.tap(find.byKey(const Key('signUpButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('닉네임·이메일·비밀번호로 가입한다(앞뒤 공백 제거)', (tester) async {
    final repo = await _pumpSignUp(tester);

    await _fill(tester, nickname: ' 새여행자 ', email: ' new@example.com ');

    expect(repo.signUpCalls.single,
        (email: 'new@example.com', password: 'secret1', nickname: '새여행자'));
  });

  testWidgets('입력 검사를 통과하지 못하면 가입 요청을 보내지 않는다', (tester) async {
    final repo = await _pumpSignUp(tester);

    await _fill(tester, nickname: '', email: 'bad', password: '123', confirm: '124');

    expect(repo.signUpCalls, isEmpty);
    expect(find.text('닉네임을 입력해 주세요.'), findsOneWidget);
    expect(find.text('이메일 형식을 확인해 주세요.'), findsOneWidget);
    expect(find.text('비밀번호는 6자 이상이어야 합니다.'), findsOneWidget);
    expect(find.text('비밀번호가 일치하지 않습니다.'), findsOneWidget);
  });

  testWidgets('이미 가입된 이메일이면 안내한다', (tester) async {
    final repo = await _pumpSignUp(tester);
    repo.nextError = const AuthException(AuthErrorCode.emailAlreadyInUse);

    await _fill(tester);

    expect(find.text('이미 가입된 이메일입니다. 이메일 또는 Google로 로그인해 주세요.'), findsOneWidget);
  });
}
```

`app/test/login/password_reset_page_test.dart` 생성:
```dart
import 'package:app/core/auth/auth_exception.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/login/password_reset_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../auth/fake_auth_repository.dart';

Future<FakeAuthRepository> _pumpReset(WidgetTester tester) async {
  final repo = FakeAuthRepository();
  addTearDown(repo.dispose);
  final router = GoRouter(
    initialLocation: '/login/reset',
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const Scaffold(body: Text('로그인 화면'))),
      GoRoute(path: '/login/reset', builder: (_, _) => const PasswordResetPage()),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _send(WidgetTester tester, String email) async {
  await tester.enterText(find.byKey(const Key('resetEmailField')), email);
  await tester.tap(find.byKey(const Key('sendResetButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('재설정 메일을 보내고 안내한다', (tester) async {
    final repo = await _pumpReset(tester);

    await _send(tester, ' me@example.com ');

    expect(repo.resetCalls, ['me@example.com']);
    expect(find.text('재설정 메일을 보냈습니다. 메일함을 확인해 주세요.'), findsOneWidget);
  });

  testWidgets('가입되지 않은 이메일이라고 와도 같은 안내를 보여준다', (tester) async {
    final repo = await _pumpReset(tester);
    repo.nextError = const AuthException(AuthErrorCode.invalidCredential);

    await _send(tester, 'nobody@example.com');

    expect(find.text('재설정 메일을 보냈습니다. 메일함을 확인해 주세요.'), findsOneWidget);
    expect(find.byKey(const Key('authError')), findsNothing);
  });

  testWidgets('네트워크 오류는 안내한다', (tester) async {
    final repo = await _pumpReset(tester);
    repo.nextError = const AuthException(AuthErrorCode.network);

    await _send(tester, 'me@example.com');

    expect(find.text('네트워크를 확인해 주세요.'), findsOneWidget);
    expect(find.text('재설정 메일을 보냈습니다. 메일함을 확인해 주세요.'), findsNothing);
  });
}
```

`app/test/router_test.dart` — `group('createRouter', ...)`의 `'로그인하지 않으면 로그인 화면이 보인다'` 테스트 다음에 추가:
```dart

    testWidgets('로그인하지 않아도 회원가입 화면에는 들어갈 수 있다', (tester) async {
      await pumpApp(tester, isLoggedIn: false);

      await tester.ensureVisible(find.byKey(const Key('signUpLink')));
      await tester.tap(find.byKey(const Key('signUpLink')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('signUpButton')), findsOneWidget);
    });
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/login/ test/router_test.dart`
Expected: FAIL — 새 파일 없음

- [ ] **Step 3: 구현 — 검사 함수와 입력칸**

`app/lib/features/login/auth_validators.dart` 생성:
```dart
/// 로그인·가입 입력 검사. 문제가 없으면 null, 있으면 칸 아래에 보여줄 문구를 돌려준다
/// (`TextFormField.validator` 형식).
library;

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateNickname(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return '닉네임을 입력해 주세요.';
  if (v.length > 20) return '닉네임은 20자 이하로 입력해 주세요.';
  return null;
}

String? validateEmail(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return '이메일을 입력해 주세요.';
  if (!_emailPattern.hasMatch(v)) return '이메일 형식을 확인해 주세요.';
  return null;
}

/// 로그인할 때는 길이를 따지지 않는다 — 규칙이 바뀌기 전에 만든 비밀번호도 있을 수 있다.
String? validateLoginPassword(String? value) =>
    (value == null || value.isEmpty) ? '비밀번호를 입력해 주세요.' : null;

/// 가입할 때의 비밀번호. Firebase 최소 길이(6자)에 맞춘다.
String? validateNewPassword(String? value) {
  if (value == null || value.isEmpty) return '비밀번호를 입력해 주세요.';
  if (value.length < 6) return '비밀번호는 6자 이상이어야 합니다.';
  return null;
}

String? validatePasswordConfirm(String? value, String password) =>
    value == password ? null : '비밀번호가 일치하지 않습니다.';
```

`app/lib/features/login/widgets/auth_text_field.dart` 생성:
```dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// 로그인·가입 화면의 라벨 + 입력칸. 테스트가 입력칸을 찾을 수 있게 [fieldKey]를 입력칸 자체에 단다.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.label,
    required this.controller,
    this.fieldKey,
    this.validator,
    this.obscureText = false,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final Key? fieldKey;
  final FormFieldValidator<String>? validator;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.borderMedium),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 6),
        TextFormField(
          key: fieldKey,
          controller: controller,
          validator: validator,
          obscureText: obscureText,
          keyboardType: keyboardType,
          autocorrect: false,
          enableSuggestions: !obscureText,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: border,
            enabledBorder: border,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: 구현 — 로그인 화면**

`app/lib/features/login/login_page.dart` 전체 교체:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_exception.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/auth/firebase_auth_repository.dart' show AuthCancelledException;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../../router.dart';
import 'auth_validators.dart';
import 'widgets/auth_text_field.dart';

/// 로그인 화면 — 이메일/비밀번호와 Google 로그인(이메일 가입 설계 §3.1).
/// 로그인에 성공하면 인증 상태가 바뀌어 라우터가 여행 탭으로 보낸다 — 이 화면이 직접 이동하지 않는다.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 로그인 요청을 보내고 실패를 문구로 바꾼다. 사용자가 Google 로그인을 취소하면 아무것도 보여주지 않는다.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthCancelledException {
      // 사용자가 닫은 것이라 알릴 게 없다.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = authErrorMessage(AuthErrorCode.unknown));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _signInWithEmail() {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(authRepositoryProvider);
    _run(() => repo.signInWithEmail(email: _email.text.trim(), password: _password.text));
  }

  void _signInWithGoogle() {
    final repo = ref.read(authRepositoryProvider);
    _run(() => repo.signInWithGoogle());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '해외여행 발걸음',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 32),
                AuthTextField(
                  label: '이메일',
                  controller: _email,
                  fieldKey: const Key('loginEmailField'),
                  validator: validateEmail,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                AuthTextField(
                  label: '비밀번호',
                  controller: _password,
                  fieldKey: const Key('loginPasswordField'),
                  validator: validateLoginPassword,
                  obscureText: true,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('authError'),
                    style: AppTextStyles.caption.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                PillButton(
                  key: const Key('emailLoginButton'),
                  label: _busy ? '로그인 중…' : '로그인',
                  onPressed: _busy ? null : _signInWithEmail,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('forgotPasswordLink'),
                    onPressed: () => context.push(AppRoutes.passwordReset),
                    child: const Text('비밀번호를 잊으셨나요?'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.borderLight)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('또는', style: AppTextStyles.caption),
                    ),
                    const Expanded(child: Divider(color: AppColors.borderLight)),
                  ],
                ),
                const SizedBox(height: 16),
                PillOutlineButton(
                  key: const Key('googleLoginButton'),
                  label: 'Google로 계속하기',
                  onPressed: _busy ? null : _signInWithGoogle,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('계정이 없으신가요?', style: AppTextStyles.caption),
                    TextButton(
                      key: const Key('signUpLink'),
                      onPressed: () => context.push(AppRoutes.signUp),
                      child: const Text('회원가입'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 구현 — 회원가입·재설정 화면**

`app/lib/features/login/sign_up_page.dart` 생성:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_exception.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../wallet/widgets/sub_page_header.dart';
import 'auth_validators.dart';
import 'widgets/auth_text_field.dart';

/// 이메일 회원가입(이메일 가입 설계 §3.2). 가입에 성공하면 로그인된 상태가 되어 라우터가 여행 탭으로 보낸다.
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nickname.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(authRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.signUpWithEmail(
        email: _email.text.trim(),
        password: _password.text,
        nickname: _nickname.text.trim(),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = authErrorMessage(AuthErrorCode.unknown));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SubPageHeader(title: '회원가입'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthTextField(
                        label: '닉네임',
                        controller: _nickname,
                        fieldKey: const Key('signUpNicknameField'),
                        validator: validateNickname,
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        label: '이메일',
                        controller: _email,
                        fieldKey: const Key('signUpEmailField'),
                        validator: validateEmail,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        label: '비밀번호 (6자 이상)',
                        controller: _password,
                        fieldKey: const Key('signUpPasswordField'),
                        validator: validateNewPassword,
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        label: '비밀번호 확인',
                        controller: _confirm,
                        fieldKey: const Key('signUpConfirmField'),
                        validator: (v) => validatePasswordConfirm(v, _password.text),
                        obscureText: true,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          key: const Key('authError'),
                          style: AppTextStyles.caption.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      PillButton(
                        key: const Key('signUpButton'),
                        label: _busy ? '가입 중…' : '가입하기',
                        onPressed: _busy ? null : _submit,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

`app/lib/features/login/password_reset_page.dart` 생성:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_exception.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../wallet/widgets/sub_page_header.dart';
import 'auth_validators.dart';
import 'widgets/auth_text_field.dart';

/// 비밀번호 재설정 메일 보내기(이메일 가입 설계 §3.3). 가입 여부를 드러내지 않도록,
/// 서버가 "없는 계정"이라고 해도 보냈다는 안내를 똑같이 보여준다.
class PasswordResetPage extends ConsumerStatefulWidget {
  const PasswordResetPage({super.key});

  @override
  ConsumerState<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends ConsumerState<PasswordResetPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(authRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
      _sent = false;
    });
    try {
      await repo.sendPasswordReset(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == AuthErrorCode.invalidCredential) {
          _sent = true;
        } else {
          _error = authErrorMessage(e.code);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = authErrorMessage(AuthErrorCode.unknown));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SubPageHeader(title: '비밀번호 재설정'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('가입한 이메일로 비밀번호 재설정 링크를 보내 드립니다.', style: AppTextStyles.body),
                      const SizedBox(height: 16),
                      AuthTextField(
                        label: '이메일',
                        controller: _email,
                        fieldKey: const Key('resetEmailField'),
                        validator: validateEmail,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      if (_sent) ...[
                        const SizedBox(height: 12),
                        Text(
                          '재설정 메일을 보냈습니다. 메일함을 확인해 주세요.',
                          key: const Key('resetSentMessage'),
                          style: AppTextStyles.caption.copyWith(color: AppColors.accent),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          key: const Key('authError'),
                          style: AppTextStyles.caption.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      PillButton(
                        key: const Key('sendResetButton'),
                        label: _busy ? '보내는 중…' : '재설정 메일 보내기',
                        onPressed: _busy ? null : _send,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: 구현 — 라우터와 진입점**

`app/lib/router.dart`:
- import 추가:
```dart
import 'features/login/password_reset_page.dart';
import 'features/login/sign_up_page.dart';
```
- `static const login = '/login';` 아래에 추가:
```dart
  /// 로그아웃 상태에서도 들어갈 수 있는 화면은 전부 /login으로 시작한다(redirect 규칙 참고).
  static const signUp = '/login/signup';
  static const passwordReset = '/login/reset';
```
- `createRouter` 시그니처와 redirect, 로그인 라우트 교체:
```dart
GoRouter createRouter({required bool isLoggedIn}) {
  return GoRouter(
    initialLocation: isLoggedIn ? AppRoutes.visa : AppRoutes.login,
    redirect: (context, state) {
      final onAuthScreen = state.matchedLocation.startsWith(AppRoutes.login);
      if (!isLoggedIn && !onAuthScreen) return AppRoutes.login;
      if (isLoggedIn && onAuthScreen) return AppRoutes.visa;
      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginPage()),
      GoRoute(path: AppRoutes.signUp, builder: (_, _) => const SignUpPage()),
      GoRoute(path: AppRoutes.passwordReset, builder: (_, _) => const PasswordResetPage()),
```
  (기존 `GoRoute(path: AppRoutes.login, builder: (context, state) => LoginPage(onSignIn: onSignIn)),` 를 위 세 줄로 바꾸고, 그 아래 `ShellRoute(...)`는 그대로 둔다.)

`app/lib/main.dart`와 `app/lib/main_dev.dart`의 `createRouter(...)` 호출을:
```dart
        router: createRouter(isLoggedIn: user != null),
```
로 바꾼다(`onSignIn:` 줄 삭제). `main_dev.dart`에서 `authRepositoryProvider` import가 override에 계속 쓰이므로 지우지 않는다. `main.dart`에서 `authRepositoryProvider`를 더 쓰지 않아 analyze가 경고하면 import는 `authStateProvider` 때문에 그대로 필요하다(같은 파일 `auth_providers.dart`).

- [ ] **Step 7: 테스트 통과 확인**

Run: `flutter test test/login/ test/router_test.dart test/auth/ && flutter test && dart analyze`
Expected: 전체 PASS, `No issues found!`

- [ ] **Step 8: 커밋**

```bash
git add app/lib/features/login app/lib/router.dart app/lib/main.dart app/lib/main_dev.dart app/test/login app/test/router_test.dart
git commit -m "feat(app): 이메일 로그인·회원가입·비밀번호 재설정 화면 추가"
```

---

### Task 3: 계정 시트와 로그아웃

**Files:**
- Create: `app/lib/features/account/account_sheet.dart`
- Modify: `app/lib/features/visa/trip_list_page.dart` (헤더)
- Test: `app/test/account/account_sheet_test.dart`, `app/test/visa/trip_list_page_test.dart`

**Interfaces:**
- Consumes: `AuthRepository.currentUser`, `signOut` (Task 1), `FakeAuthRepository.signIn/signOutCalls`
- Produces: `Future<void> showAccountSheet(BuildContext context)`, `AccountSheet` 위젯; 헤더 아이콘 키 `accountButton`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/account/account_sheet_test.dart` 생성:
```dart
import 'package:app/core/auth/app_user.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/account/account_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fake_auth_repository.dart';

Future<FakeAuthRepository> _pumpAndOpen(WidgetTester tester, AppUser user) async {
  final repo = FakeAuthRepository()..signIn(user);
  addTearDown(repo.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAccountSheet(context),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('닉네임과 이메일을 보여준다', (tester) async {
    await _pumpAndOpen(
        tester, const AppUser(uid: 'uid-abcdef', displayName: '여행자', email: 'me@example.com'));

    expect(find.text('여행자'), findsOneWidget);
    expect(find.text('me@example.com'), findsOneWidget);
  });

  testWidgets('닉네임이 없으면 uid 기반 이름을 보여준다', (tester) async {
    await _pumpAndOpen(tester, const AppUser(uid: 'abcdef123'));

    expect(find.text('여행자 abcdef'), findsOneWidget);
  });

  testWidgets('로그아웃을 누르면 시트를 닫고 로그아웃한다', (tester) async {
    final repo = await _pumpAndOpen(tester, const AppUser(uid: 'uid-abcdef', displayName: '여행자'));

    await tester.tap(find.byKey(const Key('signOutButton')));
    await tester.pumpAndSettle();

    expect(repo.signOutCalls, 1);
    expect(find.byKey(const Key('signOutButton')), findsNothing);
  });
}
```

`app/test/visa/trip_list_page_test.dart`:
- import 추가:
```dart
import 'package:app/core/auth/app_user.dart';
import 'package:app/core/auth/auth_providers.dart';

import '../auth/fake_auth_repository.dart';
```
- `_pumpList`의 `ProviderScope(overrides: [` 목록에 추가:
```dart
      authRepositoryProvider.overrideWithValue(
          FakeAuthRepository()..signIn(const AppUser(uid: 'uid-abcdef', displayName: '여행자'))),
```
- `main()` 끝에 추가:
```dart

  testWidgets('헤더의 계정 아이콘을 누르면 계정 시트가 열린다', (tester) async {
    await _pumpList(tester, trips: [sampleSummary()]);

    await tester.tap(find.byKey(const Key('accountButton')));
    await tester.pumpAndSettle();

    expect(find.text('여행자'), findsOneWidget);
    expect(find.byKey(const Key('signOutButton')), findsOneWidget);
  });
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/account/ test/visa/trip_list_page_test.dart`
Expected: FAIL — `account_sheet.dart` 없음, `accountButton` 없음

- [ ] **Step 3: 구현**

`app/lib/features/account/account_sheet.dart` 생성:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';

/// 여행 탭 헤더의 계정 아이콘에서 여는 시트(이메일 가입 설계 §3.4).
Future<void> showAccountSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      builder: (_) => const AccountSheet(),
    );

/// 표시 이름·이메일과 [로그아웃]. 로그아웃하면 인증 상태가 바뀌어 라우터가 로그인 화면으로 보낸다.
/// 가입 직후에도 닉네임이 보이도록 로그인 상태 스트림이 아니라 저장소의 최신 사용자(currentUser)를 읽는다.
class AccountSheet extends ConsumerWidget {
  const AccountSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(authRepositoryProvider);
    final user = repo.currentUser;
    final email = user?.email;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user?.displayLabel ?? '로그인 정보 없음', style: AppTextStyles.cardTitle),
            if (email != null && email.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(email, style: AppTextStyles.caption),
            ],
            const SizedBox(height: 20),
            PillOutlineButton(
              key: const Key('signOutButton'),
              label: '로그아웃',
              onPressed: () async {
                Navigator.of(context).pop();
                await repo.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

`app/lib/features/visa/trip_list_page.dart`:
- import 추가: `import '../account/account_sheet.dart';`
- 헤더 Row의 `GestureDetector(key: const Key('createTripButton'), ...)` 를 다음으로 감싼다:
```dart
              Row(
                children: [
                  GestureDetector(
                    key: const Key('createTripButton'),
                    onTap: openNew,
                    child: Text(
                      '+ 새 여행계획',
                      style: AppTextStyles.caption.copyWith(color: AppColors.accent),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('accountButton'),
                    icon: const Icon(Icons.person_outline, color: AppColors.textBody),
                    tooltip: '계정',
                    onPressed: () => showAccountSheet(context),
                  ),
                ],
              ),
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/account/ test/visa/ && flutter test && dart analyze`
Expected: 전체 PASS, `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/account app/lib/features/visa/trip_list_page.dart app/test/account app/test/visa/trip_list_page_test.dart
git commit -m "feat(app): 여행 탭 헤더에 계정 시트와 로그아웃 추가"
```

---

### Task 4: 마무리 — 실기기 확인·리뷰·PR

- [ ] **Step 1:** (사용자) Firebase 콘솔 → Authentication → Sign-in method → 이메일/비밀번호 사용 설정
- [ ] **Step 2:** 서버 실행 → `adb reverse tcp:8080 tcp:8080` → 앱 설치
- [ ] **Step 3: 사용자 실기기 확인 목록**
  1. 계정 시트에서 로그아웃 → 로그인 화면
  2. 회원가입(닉네임·이메일·비밀번호) → 자동 로그인되어 여행 탭, 계정 시트에 닉네임·이메일
  3. 로그아웃 후 이메일로 로그인, 틀린 비밀번호 안내
  4. 같은 이메일로 다시 가입 → 중복 안내
  5. 비밀번호 재설정 메일 수신 → 링크로 변경 후 새 비밀번호로 로그인
  6. Google 로그인 그대로 동작, 계정마다 여행 목록이 따로 보임
- [ ] **Step 4:** `codex review --base master` → 지적을 실제 파일로 검증 후 수정 → 트레일러 확인 → push → PR
