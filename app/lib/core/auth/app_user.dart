class AppUser {
  const AppUser({
    required this.uid,
    this.displayName,
    this.photoUrl,
    this.email,
  });

  final String uid;

  /// 로그인 수단에 따라 없을 수 있다. 이메일/비밀번호 가입 사용자는 null이다.
  final String? displayName;
  final String? photoUrl;
  final String? email;

  /// 표시용 이름. 없으면 uid 앞 6자로 대체한다.
  String get displayLabel =>
      (displayName != null && displayName!.isNotEmpty)
          ? displayName!
          : '여행자 ${uid.substring(0, 6)}';
}
