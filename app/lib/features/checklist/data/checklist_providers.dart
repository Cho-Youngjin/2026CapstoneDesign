import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import 'checklist_checked_store.dart';

final checklistCheckedStoreProvider = Provider<ChecklistCheckedStore>((ref) {
  return ChecklistCheckedStore(ref.watch(sharedPreferencesProvider));
});

/// 국가 하나(isoAlpha2)의 체크된 준비물 id 목록.
/// 토글한 뒤에 invalidate해서 다시 읽는다 — 목록이 작아서(보통 10~20개) 성능 문제는 없다.
final checklistCheckedIdsProvider =
    Provider.family<Set<int>, String>((ref, isoAlpha2) {
  return ref
      .watch(checklistCheckedStoreProvider)
      .checkedIds(isoAlpha2: isoAlpha2);
});
