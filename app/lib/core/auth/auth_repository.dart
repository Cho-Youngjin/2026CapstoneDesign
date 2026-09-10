import 'app_user.dart';

abstract class AuthRepository {
  /// 로그인 상태 변화를 방출한다. 로그아웃 상태에서는 null.
  Stream<AppUser?> authStateChanges();

  Future<AppUser> signInWithGoogle();

  Future<void> signOut();

  /// 서버 호출에 붙일 Firebase ID Token. 로그아웃 상태면 null.
  Future<String?> currentIdToken();
}
