import 'package:app/core/auth/auth_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firebase 오류 코드를 앱 오류 코드로 바꾼다', () {
    expect(mapFirebaseAuthCode('invalid-credential'), AuthErrorCode.invalidCredential);
    expect(mapFirebaseAuthCode('wrong-password'), AuthErrorCode.invalidCredential);
    expect(mapFirebaseAuthCode('user-not-found'), AuthErrorCode.invalidCredential);
    expect(mapFirebaseAuthCode('INVALID_LOGIN_CREDENTIALS'), AuthErrorCode.invalidCredential);
    expect(mapFirebaseAuthCode('email-already-in-use'), AuthErrorCode.emailAlreadyInUse);
    expect(mapFirebaseAuthCode('account-exists-with-different-credential'),
        AuthErrorCode.accountExistsWithDifferentCredential);
    expect(mapFirebaseAuthCode('weak-password'), AuthErrorCode.weakPassword);
    expect(mapFirebaseAuthCode('invalid-email'), AuthErrorCode.invalidEmail);
    expect(mapFirebaseAuthCode('network-request-failed'), AuthErrorCode.network);
    expect(mapFirebaseAuthCode('too-many-requests'), AuthErrorCode.tooManyRequests);
    expect(mapFirebaseAuthCode('user-disabled'), AuthErrorCode.unknown);
  });

  test('앱 오류 코드마다 한국어 안내 문구가 있다', () {
    expect(authErrorMessage(AuthErrorCode.invalidCredential), '이메일 또는 비밀번호가 맞지 않습니다.');
    expect(authErrorMessage(AuthErrorCode.emailAlreadyInUse),
        '이미 가입된 이메일입니다. 이메일 또는 Google로 로그인해 주세요.');
    expect(authErrorMessage(AuthErrorCode.accountExistsWithDifferentCredential),
        '이메일로 가입된 계정입니다. 이메일로 로그인해 주세요.');
    expect(authErrorMessage(AuthErrorCode.weakPassword), '비밀번호는 6자 이상이어야 합니다.');
    expect(authErrorMessage(AuthErrorCode.invalidEmail), '이메일 형식을 확인해 주세요.');
    expect(authErrorMessage(AuthErrorCode.network), '네트워크를 확인해 주세요.');
    expect(authErrorMessage(AuthErrorCode.tooManyRequests), '잠시 후 다시 시도해 주세요.');
    expect(authErrorMessage(AuthErrorCode.unknown), '로그인하지 못했습니다. 잠시 후 다시 시도해 주세요.');
  });
}
