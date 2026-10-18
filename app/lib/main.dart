import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/background/app_callback_dispatcher.dart';
import 'core/auth/auth_providers.dart';
import 'core/prefs/shared_preferences_provider.dart';
import 'core/maps/configure_google_maps.dart';
import 'features/footsteps/background/footstep_workmanager.dart';
import 'features/rate_alert/background/rate_alert_scheduler.dart';
import 'features/rate_alert/data/rate_alert_store.dart';
import 'features/visa/notifications/alarm_scheduler.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  configureGoogleMapsRendering();
  await initializeBackgroundWork();
  registerFootstepBackgroundTask();
  final prefs = await SharedPreferences.getInstance();
  // 환율 알림 작업을 저장된 설정에 맞춘다 — 백그라운드 취소와 화면 변경이 겹쳐 어긋났더라도 앱을 켜면 복구된다.
  await const WorkmanagerRateAlertScheduler().sync(enabled: await RateAlertStore(prefs).anyEnabled());
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const _Root(),
    ),
  );
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 로그아웃·계정 전환 때 이전 계정의 비자 준비 알람을 지운다(앱이 떠 있는 동안 계속 지켜본다).
    ref.watch(visaAlarmAccountGuardProvider);
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (e, _) => MaterialApp(
        home: Scaffold(body: Center(child: Text('인증 오류: $e'))),
      ),
      data: (user) => TravelFootstepsApp(
        router: createRouter(isLoggedIn: user != null),
      ),
    );
  }
}
