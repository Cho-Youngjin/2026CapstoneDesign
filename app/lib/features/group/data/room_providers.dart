import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../models/room.dart';
import 'profile_sync.dart';
import 'chat_api.dart';

/// 내가 속한 방 목록(최근 활동순). 방을 만들거나 참여한 뒤, 그리고 당겨서 새로고침할 때 invalidate한다.
///
/// 목록을 가져오기 전에 내 프로필을 서버에 맞춘다 — 그룹 탭에 들어오는 시점이면 이메일 가입자의
/// 닉네임도 이미 저장돼 있다(ProfileSync 주석 참고). 프로필 업로드 실패는 목록을 막지 않는다.
///
/// uid를 watch하므로 다른 계정으로 바뀌면 목록을 새로 가져온다.
/// `retry`를 끈다: Riverpod 기본값은 실패를 수십 초간 자동 재시도해서 오류 화면이 한참 뒤에 나온다
/// (여행 목록과 같은 이유). 재시도는 사용자가 [다시 시도]나 당겨서 새로고침으로 한다.
final myRoomsProvider = FutureProvider<List<RoomSummary>>(
  (ref) async {
    ref.watch(currentUidProvider);
    await ref.read(profileSyncProvider).ensureUploaded();
    return ref.watch(chatApiProvider).myRooms();
  },
  retry: (_, _) => null,
);
