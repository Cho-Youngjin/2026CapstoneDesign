import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../wallet/data/exchange_rate.dart';
import '../../wallet/data/exchange_rate_api.dart';
import '../../wallet/data/rate_cache.dart';
import '../../wallet/domain/currency_info.dart';
import '../data/rate_alert_store.dart';
import '../domain/rate_alert_evaluator.dart';
import '../notify/rate_notifier.dart';

/// 환율 알림 작업 한 번(설계 §6.3): 설정 읽기 → 켜진 통화마다 서버 조회 → 지갑 환율 캐시 갱신
/// → 판단 → 알림 → 바뀐 설정 저장.
///
/// 한 통화의 조회가 실패해도 다른 통화는 계속 본다. 실패한 통화는 설정을 건드리지 않으므로
/// 다음 주기(3시간 뒤)에 다시 판단한다. 그래서 항상 true(성공)를 돌려준다.
Future<bool> handleRateAlertTask({
  required RateAlertStore store,
  required ExchangeRateApi api,
  required RateCache cache,
  required RateNotifier notifier,
  required DateTime Function() now,
}) async {
  final all = await store.readAll();
  for (final entry in all.entries) {
    if (!entry.value.isEnabled) continue;
    final code = entry.key;

    final ExchangeRate rate;
    try {
      rate = await api.getRate(code);
    } catch (_) {
      continue;
    }
    final fetchedAt = now();
    // 지갑의 "몇 시간마다 원화 가치 갱신"은 이 캐시를 통해 이뤄진다(설계 §1-3, §6.3).
    await cache.write(code, RateSnapshot(rate: rate, fetchedAt: fetchedAt));

    final outcome = evaluateRateAlerts(
      settings: entry.value,
      rate: rate,
      currency: currencyInfoOf(code),
      now: fetchedAt,
    );
    for (final message in outcome.messages) {
      await notifier.show(message);
    }
    if (outcome.messages.isNotEmpty) {
      await store.save(code, outcome.settings);
    }
  }
  return true;
}

/// WorkManager isolate에서 실제 의존성을 만들어 [handleRateAlertTask]를 돌린다.
/// 이 isolate에는 Riverpod도 Firebase도 없다 — 환율 API는 로그인 없이 열려 있으므로(1단계 SecurityConfig)
/// 토큰 없는 Dio로 충분하다.
Future<bool> runRateAlertTask() async {
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(
    baseUrl: resolveBaseUrl(isAndroid: Platform.isAndroid),
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
  return handleRateAlertTask(
    store: RateAlertStore(prefs),
    api: ExchangeRateApi(dio),
    cache: RateCache(prefs),
    notifier: LocalRateNotifier(),
    now: DateTime.now,
  );
}
