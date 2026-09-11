// 개발용 진입점 — Firebase 없이 화면 UI만 빠르게 확인할 때 쓴다.
// 에뮬레이터/실기기가 없을 때 웹으로 띄워서 로그인 이후 화면들을 볼 수 있다:
//
//   flutter run -d chrome -t lib/main_dev.dart
//
// main.dart(실제 앱)는 건드리지 않는다 — 이 파일은 DevAuthRepository로 로그인을
// 흉내 낼 뿐, Google 로그인이나 서버 API를 실제로 호출하지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/auth_providers.dart';
import 'core/auth/dev_auth_repository.dart';
import 'router.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(DevAuthRepository()),
      ],
      child: const _DevRoot(),
    ),
  );
}

class _DevRoot extends ConsumerWidget {
  const _DevRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (e, _) => MaterialApp(
        home: Scaffold(body: Center(child: Text('인증 오류: $e'))),
      ),
      data: (user) => TravelFootstepsApp(
        router: createRouter(
          isLoggedIn: user != null,
          onSignIn: () => ref.read(authRepositoryProvider).signInWithGoogle(),
        ),
      ),
    );
  }
}
