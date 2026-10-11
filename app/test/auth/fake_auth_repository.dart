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
