import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../checklist/data/checklist_providers.dart';
import '../../wallet/data/wallet_database.dart';
import 'trip_api.dart';
import 'trip_list_providers.dart';

/// 여행 삭제(여행계획 중심 설계 §4.3). 서버 삭제가 성공한 뒤에만 기기 쪽 기록을 정리한다 —
/// 서버 삭제가 실패했는데 가계부부터 지우면 여행은 남고 기록만 사라진다.
class TripDeleter {
  TripDeleter(this.ref);

  final Ref ref;

  Future<void> delete(int tripId) async {
    await ref.read(tripApiProvider).deleteTrip(tripId);
    await ref.read(walletDatabaseProvider).clearWallet(tripId);
    await ref.read(powerBankCheckStoreProvider).remove(tripId);
    if (ref.read(selectedTripIdProvider) == tripId) {
      await ref.read(selectedTripIdProvider.notifier).clear();
    }
    ref.invalidate(tripListProvider);
  }
}

final tripDeleterProvider = Provider<TripDeleter>((ref) => TripDeleter(ref));
