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
