import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../data/wallet_database.dart';
import '../domain/currency_info.dart';
import '../domain/expense_category.dart';
import 'form_date_row.dart';

/// 지출 폼의 결과값. 금액은 현지 통화 최소단위.
class ExpenseInput {
  const ExpenseInput({
    required this.category,
    required this.amountMinor,
    required this.memo,
    required this.spentOn,
  });

  final ExpenseCategory category;
  final int amountMinor;
  final String memo;
  final DateTime spentOn;
}

/// 지출 기록 바텀시트를 띄운다. [initial]이 있으면 수정 모드. 저장하면 값을, 닫으면 null을 돌려준다.
Future<ExpenseInput?> showExpenseFormSheet(
  BuildContext context, {
  required CurrencyInfo currency,
  ExpenseRow? initial,
  DateTime Function() today = DateTime.now,
}) {
  return showModalBottomSheet<ExpenseInput>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) => _ExpenseFormSheet(currency: currency, initial: initial, today: today),
  );
}

class _ExpenseFormSheet extends StatefulWidget {
  const _ExpenseFormSheet({required this.currency, this.initial, required this.today});

  final CurrencyInfo currency;
  final ExpenseRow? initial;
  final DateTime Function() today;

  @override
  State<_ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends State<_ExpenseFormSheet> {
  late ExpenseCategory _category;
  late final TextEditingController _amount;
  late final TextEditingController _memo;
  late DateTime _date;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _category = initial == null ? ExpenseCategory.food : ExpenseCategory.fromCode(initial.category);
    _amount = TextEditingController(
        text: initial == null ? '' : widget.currency.toInputText(initial.amountMinor));
    _memo = TextEditingController(text: initial?.memo ?? '');
    _date = dateOnly(initial?.spentOn ?? widget.today());
  }

  @override
  void dispose() {
    _amount.dispose();
    _memo.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  void _save() {
    final minor = widget.currency.parseToMinor(_amount.text);
    if (minor == null) {
      setState(() => _error = '금액을 확인해 주세요');
      return;
    }
    Navigator.of(context).pop(ExpenseInput(
      category: _category,
      amountMinor: minor,
      memo: _memo.text.trim(),
      spentOn: _date,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.initial == null ? '지출 기록' : '지출 수정', style: AppTextStyles.screenTitle),
              const SizedBox(height: 16),
              const SectionLabel('카테고리'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in ExpenseCategory.values)
                    FilterPill(
                      key: Key('category_${c.code}'),
                      label: c.labelKo,
                      selected: c == _category,
                      onTap: () => setState(() => _category = c),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('amountField'),
                controller: _amount,
                keyboardType: TextInputType.numberWithOptions(decimal: widget.currency.minorDigits > 0),
                decoration: InputDecoration(
                  labelText: '금액',
                  suffixText: widget.currency.code,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('memoField'),
                controller: _memo,
                decoration: InputDecoration(labelText: '메모', hintText: _category.memoHint),
              ),
              const SizedBox(height: 8),
              FormDateRow(date: _date, onTap: _pickDate),
              const SizedBox(height: 16),
              PillButton(key: const Key('saveButton'), label: '저장', onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
