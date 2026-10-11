import 'package:app/features/login/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('닉네임은 공백 제외 1~20자', () {
    expect(validateNickname('  '), '닉네임을 입력해 주세요.');
    expect(validateNickname('가' * 21), '닉네임은 20자 이하로 입력해 주세요.');
    expect(validateNickname(' 여행자 '), isNull);
    expect(validateNickname('가' * 20), isNull);
  });

  test('이메일은 비어 있지 않고 형식이 맞아야 한다', () {
    expect(validateEmail(''), '이메일을 입력해 주세요.');
    expect(validateEmail('abc'), '이메일 형식을 확인해 주세요.');
    expect(validateEmail('a@b'), '이메일 형식을 확인해 주세요.');
    expect(validateEmail(' a@b.com '), isNull);
  });

  test('로그인 비밀번호는 비어 있지만 않으면 된다', () {
    expect(validateLoginPassword(''), '비밀번호를 입력해 주세요.');
    expect(validateLoginPassword('1'), isNull);
  });

  test('새 비밀번호는 6자 이상', () {
    expect(validateNewPassword(''), '비밀번호를 입력해 주세요.');
    expect(validateNewPassword('12345'), '비밀번호는 6자 이상이어야 합니다.');
    expect(validateNewPassword('123456'), isNull);
  });

  test('비밀번호 확인은 비밀번호와 같아야 한다', () {
    expect(validatePasswordConfirm('abc123', 'abc124'), '비밀번호가 일치하지 않습니다.');
    expect(validatePasswordConfirm('abc123', 'abc123'), isNull);
  });
}
