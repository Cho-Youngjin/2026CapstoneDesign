import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../data/exchange_rate.dart';
import '../domain/currency_info.dart';
import '../domain/month_day.dart';

/// 지갑 상단의 환율 배너(설계 §5.2-2). 3단계 환율 알림 화면도 이 위젯을 그대로 쓴다.
class RateBanner extends StatelessWidget {
  const RateBanner({super.key, required this.currency, required this.snapshot});

  final CurrencyInfo currency;
  final RateSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final rate = snapshot?.rate;
    return WireframeCard(
      color: AppColors.infoBg,
      borderColor: AppColors.infoBorder,
      child: rate == null
          ? Text('환율 정보 없음 · 아래로 당겨 다시 시도', style: AppTextStyles.caption)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _rateText(rate),
                        key: const Key('rateBannerRate'),
                        style: AppTextStyles.cardTitle,
                      ),
                    ),
                    if (rate.changePercent != null) _ChangeLabel(percent: rate.changePercent!),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_sourceText(rate), style: AppTextStyles.caption),
              ],
            ),
    );
  }

  String _rateText(ExchangeRate rate) {
    final unit = currency.displayUnit(rate.krwRate);
    return '${currency.unitLabel(unit)} = ${formatKrwRate(unit * rate.krwRate)}';
  }

  /// 수출입은행 값은 "고시", 참고환율은 갱신일 "기준"과 이용 조건상 필수인 출처를 붙인다.
  String _sourceText(ExchangeRate rate) {
    final date = formatMonthDay(rate.baseDate);
    return rate.isReference
        ? '$date 기준 · 참고환율 · Rates By Exchange Rate API'
        : '$date 고시 · 한국수출입은행';
  }
}

/// 전 영업일 대비 등락. 상승은 주황(warn), 하락은 파랑(accent).
class _ChangeLabel extends StatelessWidget {
  const _ChangeLabel({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String arrow;
    if (percent > 0) {
      color = AppColors.warn;
      arrow = '▲';
    } else if (percent < 0) {
      color = AppColors.accent;
      arrow = '▼';
    } else {
      color = AppColors.textSecondary;
      arrow = '-';
    }
    return Text(
      '$arrow ${percent.abs().toStringAsFixed(2)}%',
      key: const Key('rateBannerChange'),
      style: AppTextStyles.chip.copyWith(color: color, fontWeight: FontWeight.w700),
    );
  }
}
