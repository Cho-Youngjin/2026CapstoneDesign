import 'package:app/core/auth/app_user.dart';
import 'package:app/features/group/data/profile_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fake_auth_repository.dart';
import 'fake_chat_api.dart';

void main() {
  late FakeChatApi api;
  late FakeAuthRepository auth;
  late ProfileSync sync;

  setUp(() {
    api = FakeChatApi();
    auth = FakeAuthRepository();
    sync = ProfileSync(api, auth);
  });

  tearDown(() => auth.dispose());

  test('로그인한 사용자의 현재 이름·사진을 올린다', () async {
    auth.signIn(const AppUser(uid: 'uid-a', displayName: '성주', photoUrl: 'https://x/a.png'));

    await sync.ensureUploaded();

    expect(api.profileUploads, [(displayName: '성주', photoUrl: 'https://x/a.png')]);
  });

  test('값이 그대로면 다시 올리지 않는다', () async {
    auth.signIn(const AppUser(uid: 'uid-a', displayName: '성주'));

    await sync.ensureUploaded();
    await sync.ensureUploaded();
    await sync.ensureUploaded();

    expect(api.profileUploads, hasLength(1));
  });

  test('이름이 나중에 생기면 다시 올린다 — 이메일 가입은 로그인 뒤에 닉네임이 저장된다', () async {
    // 가입 직후: 로그인은 됐지만 닉네임 저장 전
    auth.signIn(const AppUser(uid: 'uid-new'));
    await sync.ensureUploaded();

    // 닉네임 저장 후
    auth.signIn(const AppUser(uid: 'uid-new', displayName: '새닉네임'));
    await sync.ensureUploaded();

    expect(api.profileUploads, [
      (displayName: null, photoUrl: null),
      (displayName: '새닉네임', photoUrl: null),
    ]);
  });

  test('다른 계정으로 바뀌면 그 계정 프로필을 올린다', () async {
    auth.signIn(const AppUser(uid: 'uid-a', displayName: '같은 이름'));
    await sync.ensureUploaded();

    auth.signIn(const AppUser(uid: 'uid-b', displayName: '같은 이름'));
    await sync.ensureUploaded();

    expect(api.profileUploads, hasLength(2));
  });

  test('로그아웃 상태면 아무것도 하지 않는다', () async {
    await sync.ensureUploaded();

    expect(api.profileUploads, isEmpty);
  });

  test('업로드에 실패해도 예외를 던지지 않고, 다음 호출 때 다시 시도한다', () async {
    auth.signIn(const AppUser(uid: 'uid-a', displayName: '성주'));
    api.profileFails = true;

    await expectLater(sync.ensureUploaded(), completes);   // 채팅 흐름을 막지 않는다

    api.profileFails = false;
    await sync.ensureUploaded();

    expect(api.profileUploads, [(displayName: '성주', photoUrl: null)]);
  });
}
