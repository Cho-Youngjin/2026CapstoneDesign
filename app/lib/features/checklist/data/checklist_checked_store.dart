import 'package:shared_preferences/shared_preferences.dart';

/// 준비물 체크 여부는 서버에 저장하지 않는다 — 국가 공통 준비물(checklist_template)에는
/// "체크했는지" 개념이 없고, 그건 이 화면을 보는 사람한테만 의미가 있다.
/// 그래서 기기 로컬(SharedPreferences)에만 저장한다.
///
/// 나라(isoAlpha2)별로 체크 상태를 따로 저장해서, 나라를 바꿨다가 다시 돌아와도
/// 예전에 체크했던 게 그대로 남아있다.
class ChecklistCheckedStore {
  ChecklistCheckedStore(this._prefs);

  final SharedPreferences _prefs;

  String _key(String isoAlpha2) => 'checklist_checked_$isoAlpha2';

  Set<int> checkedIds({required String isoAlpha2}) =>
      (_prefs.getStringList(_key(isoAlpha2)) ?? const [])
          .map(int.parse)
          .toSet();

  Future<void> toggle({
    required String isoAlpha2,
    required int templateId,
  }) async {
    final current = checkedIds(isoAlpha2: isoAlpha2);
    if (!current.add(templateId)) {
      current.remove(templateId);
    }
    await _prefs.setStringList(
      _key(isoAlpha2),
      current.map((id) => id.toString()).toList(),
    );
  }
}
