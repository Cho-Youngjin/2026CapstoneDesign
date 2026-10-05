import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 전체가 공유하는 단일 SharedPreferences provider.
///
/// 기능별로 각자 선언하면 main()에서 override한 것과 화면이 읽는 것이 서로 다른
/// 인스턴스가 되어, override를 했는데도 UnimplementedError가 나는 상황이 생긴다.
///
/// main()에서 `SharedPreferences.getInstance()`를 먼저 기다린 뒤
/// `ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)])`로
/// 실제 인스턴스를 주입해야 한다. 오버라이드하지 않고 쓰면 바로 에러를 던진다 —
/// 화면을 그리다가 조용히 실패하는 것보다, 설정을 빠뜨렸을 때 바로 알아차리는 게 낫다.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider가 오버라이드되지 않았습니다. main()에서 '
    'SharedPreferences.getInstance()를 기다린 뒤 override 해주세요.',
  );
});
