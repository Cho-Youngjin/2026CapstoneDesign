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
