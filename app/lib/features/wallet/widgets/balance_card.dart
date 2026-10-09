import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../domain/currency_info.dart';
import '../domain/wallet_summary.dart';

/// 남은 돈 카드(설계 §5.2-3). 원화 환산은 현재 환율로 계속 바뀐다.
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.currency,
    required this.summary,
    this.krwPerUnit,
  });

  final CurrencyInfo currency;
  final WalletSummary summary;

  /// 현재 1단위당 원화. 모르면 원화 환산과 평가손익을 생략한다.
  final double? krwPerUnit;

  @override
  Widget build(BuildContext context) {
    final rate = krwPerUnit;
    final gain = summary.valuationGainKrw(currency, rate);
    return WireframeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('남은 돈', style: AppTextStyles.label),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text(
                currency.format(summary.balanceMinor),
                key: const Key('balanceLocal'),
                style: AppTextStyles.screenTitle,
              ),
              if (rate != null)
                Text(
                  '≈ ${formatKrw(currency.toKrw(summary.balanceMinor, rate))}',
                  key: const Key('balanceKrw'),
                  style: AppTextStyles.chip,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '환전 ${currency.format(summary.exchangedMinor)} · 지출 ${currency.format(summary.spentMinor)}',
            style: AppTextStyles.caption,
          ),
          if (gain != null) ...[
            const SizedBox(height: 4),
            Text(
              '환전 평가손익 ${gain >= 0 ? '+' : ''}${formatKrw(gain)}',
              key: const Key('balanceGain'),
              style: AppTextStyles.caption.copyWith(
                color: gain >= 0 ? AppColors.warn : AppColors.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
