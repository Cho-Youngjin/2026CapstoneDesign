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
      GoRoute(path: '/login/signup', builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('가입 화면'))),
      GoRoute(path: '/login/reset', builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('재설정 화면'))),
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
