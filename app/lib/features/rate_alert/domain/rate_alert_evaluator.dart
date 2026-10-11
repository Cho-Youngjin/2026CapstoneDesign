import '../../wallet/data/exchange_rate.dart';
import '../../wallet/domain/currency_info.dart';
import 'rate_alert_settings.dart';

/// 보낼 알림 하나.
class RateAlertMessage {
  const RateAlertMessage({required this.notificationId, required this.title, required this.body});

  /// 같은 id로 다시 보내면 이전 알림을 덮어쓴다(통화별 등락 알림은 하나만 남는다).
  final int notificationId;
  final String title;
  final String body;
}

/// 판단 결과: 저장할 새 설정 + 보낼 알림.
class RateAlertOutcome {
  const RateAlertOutcome({required this.settings, required this.messages});

  final RateAlertSettings settings;
  final List<RateAlertMessage> messages;
}

/// 환율 알림 판단(설계 §6.4). 부수효과가 없는 순수 함수라 백그라운드 작업과 분리해 테스트한다.
///
/// - 전일 대비: 매일 알림이 켜져 있고, 아직 알리지 않은 고시일이며, 이전값이 있을 때 → 고시일 기록
/// - 목표 도달: 켜진 목표가 조건을 만족하면 → 끄고 도달 시각 기록(한 번만 울린다)
RateAlertOutcome evaluateRateAlerts({
  required RateAlertSettings settings,
  required ExchangeRate rate,
  required CurrencyInfo currency,
  required DateTime now,
}) {
  final messages = <RateAlertMessage>[];

  var lastDaily = settings.lastDailyBaseDate;
  final previous = rate.previousKrwRate;
  if (settings.daily && previous != null && !_sameDate(rate.baseDate, lastDaily)) {
    messages.add(_dailyMessage(rate, previous, currency));
    lastDaily = rate.baseDate;
  }

  final targets = <RateTarget>[];
  for (final t in settings.targets) {
    if (t.active && isTargetReached(t, rate.krwRate)) {
      targets.add(t.copyWith(active: false, firedAt: now));
      messages.add(_targetMessage(t, rate, currency));
    } else {
      targets.add(t);
    }
  }

  return RateAlertOutcome(
    settings: settings.copyWith(lastDailyBaseDate: lastDaily, targets: targets),
    messages: messages,
  );
}

/// 목표 도달 여부. 표시 단위 금액(예: 100엔당 847.46원)을 전(0.01원) 단위 정수로 반올림해 비교한다 —
/// 실수끼리 바로 비교하면 8.4746 × 100이 847.4599…가 되어 "같을 때 발송"이 깨진다.
bool isTargetReached(RateTarget target, double krwPerUnit) {
  final current = _cents(krwPerUnit * target.unit);
  final goal = _cents(target.targetKrw);
  return target.direction == TargetDirection.below ? current <= goal : current >= goal;
}

/// 통화별 등락 알림 id. 목표 알림 id(10억 미만)와 겹치지 않게 10억대를 쓴다.
/// String.hashCode는 실행마다 같다는 보장이 없어 직접 계산한다.
int dailyNotificationId(String currencyCode) {
  var hash = 0;
  for (final c in currencyCode.toUpperCase().codeUnits) {
    hash = (hash * 31 + c) % 100000;
  }
  return 1000000000 + hash;
}

int _cents(double won) => (won * 100).round();

bool _sameDate(DateTime a, DateTime? b) =>
    b != null && a.year == b.year && a.month == b.month && a.day == b.day;

RateAlertMessage _dailyMessage(ExchangeRate rate, double previous, CurrencyInfo currency) {
  final unit = currency.displayUnit(rate.krwRate);
  final head = '${currency.nameKo} ${currency.unitLabel(unit)} ${formatKrwRate(unit * rate.krwRate)}';
  final diff = unit * (rate.krwRate - previous);
  final percent = rate.changePercent ?? (rate.krwRate - previous) / previous * 100;
  final String tail;
  if (_cents(diff) == 0) {
    tail = '전 영업일과 같아요';
  } else {
    final arrow = diff > 0 ? '▲' : '▼';
    tail = '전 영업일보다 $arrow${formatKrwRate(diff.abs())}(${percent.abs().toStringAsFixed(2)}%)';
  }
  return RateAlertMessage(
    notificationId: dailyNotificationId(currency.code),
    title: '환율 등락 알림',
    body: '$head · $tail',
  );
}

RateAlertMessage _targetMessage(RateTarget target, ExchangeRate rate, CurrencyInfo currency) {
  final now = formatKrwRate(target.unit * rate.krwRate);
  return RateAlertMessage(
    notificationId: target.id,
    title: '목표 환율 도달',
    body: '${currency.nameKo} ${currency.unitLabel(target.unit)} $now '
        '(목표 ${formatTargetKrw(target.targetKrw)} ${target.direction.labelKo})',
  );
}
