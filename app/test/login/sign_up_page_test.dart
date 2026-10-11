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
