import 'package:app/core/auth/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';

void main() {
  group('AppUser', () {
    test('displayName이 있으면 그대로 쓴다', () {
      const user = AppUser(uid: 'abcdef123', displayName: '조영진');
      expect(user.displayLabel, '조영진');
    });

    test('displayName이 null이면 uid 기반 이름으로 대체한다', () {
      const user = AppUser(uid: 'abcdef123');
      expect(user.displayLabel, '여행자 abcdef');
    });

    test('displayName이 빈 문자열이어도 대체한다', () {
      const user = AppUser(uid: 'abcdef123', displayName: '');
      expect(user.displayLabel, '여행자 abcdef');
    });
  });

  group('AuthRepository 계약', () {
    late FakeAuthRepository repo;

    setUp(() => repo = FakeAuthRepository());
    tearDown(() => repo.dispose());

    test('초기 상태는 로그아웃이다', () async {
      expect(await repo.authStateChanges().first, isNull);
      expect(await repo.currentIdToken(), isNull);
    });

    test('로그인하면 사용자와 토큰이 생긴다', () async {
      final user = await repo.signInWithGoogle();

      expect(user.uid, 'uid-123');
      expect(await repo.currentIdToken(), 'valid-token');
    });

    test('로그아웃하면 스트림이 null을 방출한다', () async {
      await repo.signInWithGoogle();
      final future = repo.authStateChanges().firstWhere((u) => u == null);

      await repo.signOut();

      expect(await future, isNull);
      expect(await repo.currentIdToken(), isNull);
    });
  });
}
