import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../domain/rate_alert_settings.dart';

/// 통화별 환율 알림 설정을 기기에 저장한다(설계 §6.2, 키 `rateAlerts.v1`).
///
/// 화면(앱 isolate)과 백그라운드 작업(WorkManager isolate)이 같은 값을 읽고 쓴다.
/// SharedPreferences는 isolate마다 메모리 캐시를 따로 두므로, 읽기 전에 항상 `reload()`로
/// 디스크 값을 다시 가져온다 — 그래야 화면이 백그라운드가 기록한 "도달함"을 옛 값으로 덮어쓰지 않는다.
class RateAlertStore {
  RateAlertStore(this._prefs);

  final SharedPreferences _prefs;

  static const key = 'rateAlerts.v1';

  Future<Map<String, RateAlertSettings>> readAll() async {
    await _prefs.reload();
    final raw = _prefs.getString(key);
    if (raw == null) return {};
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return {}; // 깨진 값은 없는 것으로 보고, 다음 저장 때 덮어쓴다.
    } on TypeError {
      return {}; // 최상위가 Map이 아닌 경우.
    }
    // 통화 하나만 깨져도 나머지는 살린다 — 아니면 다음 save가 정상 통화의 설정까지 지운다.
    final result = <String, RateAlertSettings>{};
    for (final e in json.entries) {
      try {
        result[e.key] = RateAlertSettings.fromJson(e.value as Map<String, dynamic>);
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return result;
  }

  Future<RateAlertSettings> read(String currencyCode) async =>
      (await readAll())[currencyCode.toUpperCase()] ?? RateAlertSettings.empty;

  /// 한 통화만 바꾼다. 저장 직전에 전체를 다시 읽어 다른 통화의 최신 값을 보존한다.
  Future<void> save(String currencyCode, RateAlertSettings settings) async {
    final all = await readAll();
    all[currencyCode.toUpperCase()] = settings;
    await _prefs.setString(key, jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}));
  }

  /// 백그라운드 작업을 등록해 둘지 판단할 때 쓴다.
  Future<bool> anyEnabled() async => (await readAll()).values.any((s) => s.isEnabled);
}

final rateAlertStoreProvider = Provider<RateAlertStore>((ref) {
  return RateAlertStore(ref.watch(sharedPreferencesProvider));
});

/// 통화 코드별 알림 설정. 화면에서 바꾼 뒤에는 이 프로바이더를 invalidate 한다.
final rateAlertSettingsProvider = FutureProvider.family<RateAlertSettings, String>((ref, currencyCode) {
  return ref.watch(rateAlertStoreProvider).read(currencyCode);
});
