import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_user.dart';
import 'auth_repository.dart';
import 'firebase_auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// 지금 로그인한 계정의 uid. 로그아웃 상태이거나 아직 알 수 없으면 null.
/// 기기에 저장하는 계정별 값(여행 목록 캐시, 선택된 여행)의 키를 이 값으로 나눈다.
final currentUidProvider = Provider<String?>((ref) => ref.watch(authStateProvider).value?.uid);
