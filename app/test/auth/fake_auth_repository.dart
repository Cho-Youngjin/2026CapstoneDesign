import 'dart:async';

import 'package:app/core/auth/app_user.dart';
import 'package:app/core/auth/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current;
  String? _idToken;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    _current = const AppUser(uid: 'uid-123', displayName: '테스터', email: 't@example.com');
    _idToken = 'valid-token';
    _controller.add(_current);
    return _current!;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _idToken = null;
    _controller.add(null);
  }

  @override
  Future<String?> currentIdToken() async => _idToken;

  void dispose() => _controller.close();
}
