import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../../visa/data/trip_api.dart';
import '../../visa/models/trip_checklist_item.dart';
import 'power_bank_check_store.dart';

final powerBankCheckStoreProvider = Provider<PowerBankCheckStore>((ref) {
  return PowerBankCheckStore(ref.watch(sharedPreferencesProvider));
});

/// 여행 하나의 보조배터리 체크 여부. 토글한 뒤 invalidate해서 다시 읽는다.
final powerBankCheckedProvider = Provider.family<bool, int>((ref, tripId) {
  return ref.watch(powerBankCheckStoreProvider).isChecked(tripId);
});

/// 여행 하나의 서버 준비물 목록(체크 여부 포함). 화면을 떠나면 버리고 다시 들어오면 새로 읽는다.
final tripChecklistProvider =
    FutureProvider.autoDispose.family<List<TripChecklistItem>, int>((ref, tripId) {
  return ref.watch(tripApiProvider).getChecklist(tripId);
});
