import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../data/wallet_database.dart';
import '../domain/currency_info.dart';
import 'form_date_row.dart';

/// 환전 폼의 결과값. [amountMinor]는 받은 현지 통화 최소단위, [krwPaid]는 낸 원화(선택).
class ExchangeInput {
  const ExchangeInput({
    required this.amountMinor,
    required this.krwPaid,
    required this.memo,
    required this.exchangedOn,
  });

  final int amountMinor;
  final int? krwPaid;
  final String memo;
  final DateTime exchangedOn;
}

/// 환전 기록 바텀시트를 띄운다. [initial]이 있으면 수정 모드.
Future<ExchangeInput?> showExchangeFormSheet(
  BuildContext context, {
  required CurrencyInfo currency,
  ExchangeRow? initial,
  DateTime Function() today = DateTime.now,
}) {
  return showModalBottomSheet<ExchangeInput>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) => _ExchangeFormSheet(currency: currency, initial: initial, today: today),
  );
}

class _ExchangeFormSheet extends StatefulWidget {
  const _ExchangeFormSheet({required this.currency, this.initial, required this.today});

  final CurrencyInfo currency;
  final ExchangeRow? initial;
  final DateTime Function() today;

  @override
  State<_ExchangeFormSheet> createState() => _ExchangeFormSheetState();
}

class _ExchangeFormSheetState extends State<_ExchangeFormSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _krwPaid;
  late final TextEditingController _memo;
  late DateTime _date;
  String? _amountError;
  String? _krwError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _amount = TextEditingController(
        text: initial == null ? '' : widget.currency.toInputText(initial.amountMinor));
    _krwPaid = TextEditingController(text: initial?.krwPaid?.toString() ?? '');
    _memo = TextEditingController(text: initial?.memo ?? '');
    _date = dateOnly(initial?.exchangedOn ?? widget.today());
  }

  @override
  void dispose() {
    _amount.dispose();
    _krwPaid.dispose();
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
    final krwText = _krwPaid.text.replaceAll(',', '').trim();
    final krw = krwText.isEmpty ? null : int.tryParse(krwText);
    final krwInvalid = krwText.isNotEmpty && (krw == null || krw <= 0);
    setState(() {
      _amountError = minor == null ? '금액을 확인해 주세요' : null;
      _krwError = krwInvalid ? '원화 금액을 확인해 주세요' : null;
    });
    if (minor == null || krwInvalid) return;
    Navigator.of(context).pop(ExchangeInput(
      amountMinor: minor,
      krwPaid: krw,
      memo: _memo.text.trim(),
      exchangedOn: _date,
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
              Text(widget.initial == null ? '환전 기록' : '환전 수정', style: AppTextStyles.screenTitle),
              const SizedBox(height: 16),
              TextField(
                key: const Key('exchangeAmountField'),
                controller: _amount,
                keyboardType: TextInputType.numberWithOptions(decimal: widget.currency.minorDigits > 0),
                decoration: InputDecoration(
                  labelText: '받은 금액',
                  suffixText: widget.currency.code,
                  errorText: _amountError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('krwPaidField'),
                controller: _krwPaid,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '낸 원화 (선택)',
                  suffixText: '원',
                  errorText: _krwError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('exchangeMemoField'),
                controller: _memo,
                decoration: const InputDecoration(labelText: '메모', hintText: '공항 환전, 현지 ATM 등'),
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
