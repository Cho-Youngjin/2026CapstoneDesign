import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import 'exchange_rate.dart';

/// 통화별 마지막 환율을 기기에 저장한다(설계 §5.5). 해외에서 데이터가 끊겨도
/// 지갑이 마지막 값과 고시일을 보여줄 수 있게 하기 위해서다.
class RateCache {
  RateCache(this._prefs);

  final SharedPreferences _prefs;

  static String keyOf(String currencyCode) => 'rateCache.${currencyCode.toUpperCase()}';

  RateSnapshot? read(String currencyCode) {
    final raw = _prefs.getString(keyOf(currencyCode));
    if (raw == null) return null;
    try {
      return RateSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null; // 깨진 캐시는 없는 것으로 보고, 다음 조회 때 덮어쓴다.
    } on TypeError {
      return null; // 예전 형식으로 저장된 값도 마찬가지다.
    }
  }

  Future<void> write(String currencyCode, RateSnapshot snapshot) =>
      _prefs.setString(keyOf(currencyCode), jsonEncode(snapshot.toJson()));
}

final rateCacheProvider = Provider<RateCache>((ref) {
  return RateCache(ref.watch(sharedPreferencesProvider));
});
