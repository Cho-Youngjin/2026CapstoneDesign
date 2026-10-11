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
