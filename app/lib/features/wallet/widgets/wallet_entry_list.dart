import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../data/wallet_database.dart';
import '../domain/currency_info.dart';
import '../domain/expense_category.dart';
import '../domain/month_day.dart';
import '../domain/wallet_entries.dart';

/// 날짜별 기록 목록(설계 §5.2-5). 지출의 원화는 기록 시점 환율로 고정하고,
/// 환전의 원화는 현재 환율로 계속 바뀐다(설계 §5.3).
class WalletEntryList extends StatelessWidget {
  const WalletEntryList({
    super.key,
    required this.entries,
    required this.currency,
    this.currentKrwPerUnit,
    required this.onTapExpense,
    required this.onTapExchange,
    required this.onLongPressExpense,
    required this.onLongPressExchange,
  });

  final List<WalletEntry> entries;
  final CurrencyInfo currency;
  final double? currentKrwPerUnit;
  final ValueChanged<ExpenseRow> onTapExpense;
  final ValueChanged<ExchangeRow> onTapExchange;
  final ValueChanged<ExpenseRow> onLongPressExpense;
  final ValueChanged<ExchangeRow> onLongPressExchange;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '아직 기록이 없습니다. 아래 버튼으로 지출이나 환전을 기록해 보세요.',
          style: AppTextStyles.caption,
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (day, dayEntries) in groupByDate(entries)) ...[
          const SizedBox(height: 10),
          SectionLabel(formatMonthDay(day)),
          for (final entry in dayEntries) _row(entry),
        ],
      ],
    );
  }

  Widget _row(WalletEntry entry) {
    switch (entry) {
      case ExpenseEntry(:final row):
        final category = ExpenseCategory.fromCode(row.category);
        final rateAtEntry = row.krwPerUnitAtEntry;
        return _EntryRow(
          key: Key('entry_expense_${row.id}'),
          kind: category.labelKo,
          title: row.memo.isEmpty ? category.labelKo : row.memo,
          amount: currency.format(row.amountMinor),
          krw: rateAtEntry == null
              ? '환율 없음'
              : '≈ ${formatKrw(currency.toKrw(row.amountMinor, rateAtEntry))}',
          onTap: () => onTapExpense(row),
          onLongPress: () => onLongPressExpense(row),
        );
      case ExchangeEntry(:final row):
        final rate = currentKrwPerUnit;
        return _EntryRow(
          key: Key('entry_exchange_${row.id}'),
          kind: '환전',
          title: row.memo.isEmpty ? '환전' : row.memo,
          amount: '+${currency.format(row.amountMinor)}',
          krw: rate == null ? '' : '≈ ${formatKrw(currency.toKrw(row.amountMinor, rate))}',
          onTap: () => onTapExchange(row),
          onLongPress: () => onLongPressExchange(row),
        );
    }
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.kind,
    required this.title,
    required this.amount,
    required this.krw,
    required this.onTap,
    required this.onLongPress,
  });

  final String kind;
  final String title;
  final String amount;
  final String krw;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
        ),
        child: Row(
          children: [
            SizedBox(width: 44, child: Text(kind, style: AppTextStyles.chip)),
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(amount, style: AppTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
                if (krw.isNotEmpty) Text(krw, style: AppTextStyles.caption),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
