import 'package:shared_preferences/shared_preferences.dart';

/// 보조배터리 행은 서버 준비물이 아니라 앱이 국가 정보로 만드는 행이라(power_bank_item.dart),
/// 체크 여부만 기기에 여행별로 저장한다. 나머지 준비물의 체크는 서버(trip_checklist)에 있다.
class PowerBankCheckStore {
  PowerBankCheckStore(this._prefs);

  final SharedPreferences _prefs;

  String _key(int tripId) => 'checklist_powerbank_$tripId';

  bool isChecked(int tripId) => _prefs.getBool(_key(tripId)) ?? false;

  Future<void> setChecked(int tripId, bool checked) async {
    await _prefs.setBool(_key(tripId), checked);
  }

  /// 여행을 지울 때 함께 지운다.
  Future<void> remove(int tripId) async {
    await _prefs.remove(_key(tripId));
  }
}
