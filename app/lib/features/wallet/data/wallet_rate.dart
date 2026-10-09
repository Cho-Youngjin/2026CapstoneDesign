import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'exchange_rate.dart';
import 'exchange_rate_api.dart';
import 'rate_cache.dart';

/// 캐시를 먼저 내보내고(오프라인에서도 화면이 바로 그려지게) 서버에서 새 값을 받으면 한 번 더 내보낸다.
/// 서버가 실패하면 캐시만 남는다. 캐시도 없고 서버도 실패하면 null 하나(= "환율 정보 없음").
Stream<RateSnapshot?> loadWalletRate({
  required RateCache cache,
  required ExchangeRateApi api,
  required DateTime Function() now,
  required String currencyCode,
}) async* {
  final cached = cache.read(currencyCode);
  if (cached != null) yield cached;
  try {
    final fresh = RateSnapshot(rate: await api.getRate(currencyCode), fetchedAt: now());
    await cache.write(currencyCode, fresh);
    yield fresh;
  } catch (_) {
    // 네트워크·서버 오류는 화면을 막지 않는다: 캐시가 있으면 이미 내보냈다.
    if (cached == null) yield null;
  }
}

/// 통화 코드별 지갑 환율. 당겨서 새로고침은 이 프로바이더를 invalidate 한다.
final walletRateProvider =
    StreamProvider.family<RateSnapshot?, String>((ref, currencyCode) {
  return loadWalletRate(
    cache: ref.watch(rateCacheProvider),
    api: ref.watch(exchangeRateApiProvider),
    now: DateTime.now,
    currencyCode: currencyCode,
  );
});
