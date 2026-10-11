/// 로그인·가입 실패의 종류. Firebase 오류 코드를 화면이 알 필요 없게 이 값으로 바꿔 던진다.
enum AuthErrorCode {
  invalidCredential,
  emailAlreadyInUse,
  accountExistsWithDifferentCredential,
  weakPassword,
  invalidEmail,
  network,
  tooManyRequests,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.code);

  final AuthErrorCode code;

  @override
  String toString() => authErrorMessage(code);
}

/// Firebase Auth 오류 코드 → 앱 오류 코드. 모르는 코드는 [AuthErrorCode.unknown].
/// 이메일 열거 보호가 켜진 프로젝트는 틀린 비밀번호·없는 계정을 모두 invalid-credential로 준다.
AuthErrorCode mapFirebaseAuthCode(String code) => switch (code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'INVALID_LOGIN_CREDENTIALS' =>
        AuthErrorCode.invalidCredential,
      'email-already-in-use' => AuthErrorCode.emailAlreadyInUse,
      'account-exists-with-different-credential' =>
        AuthErrorCode.accountExistsWithDifferentCredential,
      'weak-password' => AuthErrorCode.weakPassword,
      'invalid-email' => AuthErrorCode.invalidEmail,
      'network-request-failed' => AuthErrorCode.network,
      'too-many-requests' => AuthErrorCode.tooManyRequests,
      _ => AuthErrorCode.unknown,
    };

/// 화면에 보여줄 안내 문구. 이미 가입된 이메일이 Google 계정인지 이메일 계정인지는 Firebase가
/// 알려주지 않으므로 두 경우를 함께 안내한다.
String authErrorMessage(AuthErrorCode code) => switch (code) {
      AuthErrorCode.invalidCredential => '이메일 또는 비밀번호가 맞지 않습니다.',
      AuthErrorCode.emailAlreadyInUse => '이미 가입된 이메일입니다. 이메일 또는 Google로 로그인해 주세요.',
      AuthErrorCode.accountExistsWithDifferentCredential => '이메일로 가입된 계정입니다. 이메일로 로그인해 주세요.',
      AuthErrorCode.weakPassword => '비밀번호는 6자 이상이어야 합니다.',
      AuthErrorCode.invalidEmail => '이메일 형식을 확인해 주세요.',
      AuthErrorCode.network => '네트워크를 확인해 주세요.',
      AuthErrorCode.tooManyRequests => '잠시 후 다시 시도해 주세요.',
      AuthErrorCode.unknown => '로그인하지 못했습니다. 잠시 후 다시 시도해 주세요.',
    };
