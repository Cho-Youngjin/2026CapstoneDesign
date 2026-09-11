import 'dart:async';

import 'app_user.dart';
import 'auth_repository.dart';

/// 개발용 가짜 로그인 구현체. Firebase 없이 화면 UI만 확인하고 싶을 때
/// (에뮬레이터/실기기가 없어 `flutter run -d chrome` 등으로 웹에서 테스트할 때)
/// `main_dev.dart` 진입점에서만 사용한다 — 실제 앱(main.dart)은 이 파일을 쓰지 않는다.
///
/// 항상 로그인된 상태로 시작하며, 서버 API는 실제로 호출하지 않으므로
/// currentIdToken()도 진짜 토큰이 아니라 더미 문자열을 반환한다(서버 없이도
/// 화면이 죽지 않게 하려는 목적 — 실제 API 응답은 받지 못한다).
class DevAuthRepository implements AuthRepository {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current = const AppUser(
    uid: 'dev-user',
    displayName: '개발용 테스터',
    email: 'dev@example.com',
  );

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    _current = const AppUser(
      uid: 'dev-user',
      displayName: '개발용 테스터',
      email: 'dev@example.com',
    );
    _controller.add(_current);
    return _current!;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  @override
  Future<String?> currentIdToken() async => 'dev-fake-token';
}
