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
///
/// `retry`를 끈다: 실패하면 Riverpod이 자동 재시도하느라 오류 표시가 늦어지므로,
/// 재시도는 사용자가 [다시 시도]로 한다.
final tripChecklistProvider = FutureProvider.autoDispose.family<List<TripChecklistItem>, int>(
  (ref, tripId) => ref.watch(tripApiProvider).getChecklist(tripId),
  retry: (_, _) => null,
);
