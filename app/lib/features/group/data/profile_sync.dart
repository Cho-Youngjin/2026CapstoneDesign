import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/auth/auth_repository.dart';
import 'chat_api.dart';

/// 채팅에 보일 내 이름·사진을 서버(`PUT /api/me/profile`)에 맞춰 둔다.
///
/// <b>왜 "로그인할 때 한 번"이 아니라 "필요할 때마다 확인"인가</b>: 이메일 가입은 로그인 이벤트가
/// 먼저 나가고 닉네임은 그 뒤에 저장된다(AuthRepository.currentUser 주석 참고). 로그인 순간에만
/// 올리면 이메일 가입자는 이름 없이 올라가 채팅에서 "알 수 없음"으로 보인다. 그래서 그룹 탭에
/// 들어갈 때와 방을 만들거나 참여하기 직전에 [ensureUploaded]를 부르고, 그때의 최신 값
/// ([AuthRepository.currentUser])이 마지막으로 올린 값과 다를 때만 올린다.
///
/// 업로드 실패는 삼킨다 — 프로필은 표시용이라, 이것 때문에 채팅 목록이나 방 만들기가 막히면 안 된다.
/// 실패하면 "올린 값"을 기억하지 않으므로 다음 호출 때 자연히 다시 시도한다.
class ProfileSync {
  ProfileSync(this._api, this._auth);

  final ChatApi _api;
  final AuthRepository _auth;

  ({String uid, String? displayName, String? photoUrl})? _lastUploaded;

  Future<void> ensureUploaded() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final current = (uid: user.uid, displayName: user.displayName, photoUrl: user.photoUrl);
    if (current == _lastUploaded) return;

    try {
      await _api.putProfile(displayName: user.displayName, photoUrl: user.photoUrl);
      _lastUploaded = current;
    } catch (e) {
      debugPrint('프로필 업로드 실패(다음에 다시 시도): $e');
    }
  }
}

/// 앱이 살아 있는 동안 하나만 유지한다 — "마지막으로 올린 값"을 기억해야 중복 업로드를 막는다.
final profileSyncProvider = Provider<ProfileSync>(
  (ref) => ProfileSync(ref.watch(chatApiProvider), ref.watch(authRepositoryProvider)),
);
