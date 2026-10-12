/// 로그인·가입 입력 검사. 문제가 없으면 null, 있으면 칸 아래에 보여줄 문구를 돌려준다
/// (`TextFormField.validator` 형식).
library;

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateNickname(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return '닉네임을 입력해 주세요.';
  if (v.length > 20) return '닉네임은 20자 이하로 입력해 주세요.';
  return null;
}

String? validateEmail(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return '이메일을 입력해 주세요.';
  if (!_emailPattern.hasMatch(v)) return '이메일 형식을 확인해 주세요.';
  return null;
}

/// 로그인할 때는 길이를 따지지 않는다 — 규칙이 바뀌기 전에 만든 비밀번호도 있을 수 있다.
String? validateLoginPassword(String? value) =>
    (value == null || value.isEmpty) ? '비밀번호를 입력해 주세요.' : null;

/// 가입할 때의 비밀번호. Firebase 최소 길이(6자)에 맞춘다.
String? validateNewPassword(String? value) {
  if (value == null || value.isEmpty) return '비밀번호를 입력해 주세요.';
  if (value.length < 6) return '비밀번호는 6자 이상이어야 합니다.';
  return null;
}

String? validatePasswordConfirm(String? value, String password) =>
    value == password ? null : '비밀번호가 일치하지 않습니다.';
