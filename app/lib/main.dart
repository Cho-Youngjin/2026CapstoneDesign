import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/auth/auth_providers.dart';
import 'core/prefs/shared_preferences_provider.dart';
import 'core/maps/configure_google_maps.dart';
import 'features/footsteps/background/footstep_workmanager.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  configureGoogleMapsRendering();
  registerFootstepBackgroundTask();
  final prefs = await SharedPreferences.getInstance();
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
