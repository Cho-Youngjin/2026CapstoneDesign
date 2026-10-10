import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/country_detail_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../wallet/data/exchange_rate.dart';
import '../wallet/data/wallet_rate.dart';
import '../wallet/domain/currency_info.dart';
import '../wallet/domain/month_day.dart';
import '../wallet/widgets/rate_banner.dart';
import '../wallet/widgets/sub_page_header.dart';
import 'background/rate_alert_scheduler.dart';
import 'data/rate_alert_store.dart';
import 'domain/rate_alert_evaluator.dart';
import 'domain/rate_alert_settings.dart';
import 'notify/notification_permission.dart';

/// 환율 알림 설정 화면 — 지갑·환율 알림 설계 §6.1.
/// 준비물 탭 환전 섹션의 `환율 알림 ›`에서 `/checklist/rate-alert?iso=JP`로 들어온다.
class RateAlertPage extends ConsumerStatefulWidget {
  const RateAlertPage({super.key, required this.isoAlpha2});

  final String isoAlpha2;

  @override
  ConsumerState<RateAlertPage> createState() => _RateAlertPageState();
}

class _RateAlertPageState extends ConsumerState<RateAlertPage> {
  final _amount = TextEditingController();
  TargetDirection _direction = TargetDirection.below;
  String? _amountError;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(countryDetailProvider(widget.isoAlpha2));
    return detailAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Notice(title: '환율 알림', message: '국가 정보를 불러오지 못했습니다: $e'),
      data: (detail) {
        final code = detail.currencyCode?.trim();
        if (code == null || code.isEmpty) {
          return _Notice(
            title: '${detail.nameKo} 환율 알림',
            message: '이 나라의 통화 정보가 없어 환율 알림을 쓸 수 없습니다.',
          );
        }
        return _page(detail, currencyInfoOf(code));
      },
    );
  }

  Widget _page(CountryDetail detail, CurrencyInfo currency) {
    final snapshot = ref.watch(walletRateProvider(currency.code)).value;
    final settings = ref.watch(rateAlertSettingsProvider(currency.code)).value;

    return Column(
      children: [
        SubPageHeader(title: '${detail.nameKo} 환율 알림'),
        Expanded(
          child: settings == null
              ? const Center(child: CircularProgressIndicator())
              // 배너의 "아래로 당겨 다시 시도" 안내가 지갑과 똑같이 동작하게 한다.
              : RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(walletRateProvider(currency.code));
                    await ref.read(walletRateProvider(currency.code).future);
                  },
                  child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  children: [
                    RateBanner(currency: currency, snapshot: snapshot),
                    const SizedBox(height: 18),
                    const SectionLabel('등락 알림'),
                    const SizedBox(height: 4),
                    _DailyRow(
                      value: settings.daily,
                      onChanged: (on) => _setDaily(currency.code, on),
                    ),
                    const SizedBox(height: 18),
                    const SectionLabel('목표 환율'),
                    const SizedBox(height: 4),
                    if (settings.targets.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('아직 목표가 없습니다.', style: AppTextStyles.caption),
                      ),
                    for (final t in settings.targets)
                      _TargetRow(
                        currency: currency,
                        target: t,
                        onToggle: (on) => _toggleTarget(currency.code, t.id, on),
                        onDelete: () => _deleteTarget(currency.code, t.id),
                      ),
                    const SizedBox(height: 16),
                    if (snapshot == null)
                      Text('환율 정보를 받은 뒤에 목표를 추가할 수 있어요.', style: AppTextStyles.caption)
                    else
                      _addForm(currency, snapshot.rate),
                  ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _addForm(CurrencyInfo currency, ExchangeRate rate) {
    final unit = currency.displayUnit(rate.krwRate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterPill(
              key: const Key('direction_BELOW'),
              label: '이하로 내려가면',
              selected: _direction == TargetDirection.below,
              onTap: () => setState(() => _direction = TargetDirection.below),
            ),
            FilterPill(
              key: const Key('direction_ABOVE'),
              label: '이상으로 오르면',
              selected: _direction == TargetDirection.above,
              onTap: () => setState(() => _direction = TargetDirection.above),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('targetAmountField'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '${currency.unitLabel(unit)}당 목표 환율',
            hintText: '지금 ${formatKrwRate(unit * rate.krwRate)}',
            suffixText: '원',
            errorText: _amountError,
          ),
        ),
        const SizedBox(height: 12),
        PillButton(
          key: const Key('addTargetButton'),
          label: '목표 추가',
          onPressed: () => _addTarget(currency.code, unit, rate),
        ),
      ],
    );
  }

  /// 알림을 켜는 동작 전에 권한을 받는다. 거부되면 저장하지 않으므로 스위치는 원래 값으로 남는다.
  Future<bool> _ensurePermission() async {
    final granted = await ref.read(notificationPermissionProvider).request();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('알림 권한이 꺼져 있어 환율 알림을 켤 수 없어요. 설정에서 알림을 허용해 주세요.'),
      ));
    }
    return granted;
  }

  /// 저장소의 최신 값에 [change]를 적용해 저장하고, 켜진 알림 유무에 맞춰 백그라운드 작업을 등록/취소한다.
  /// 화면이 들고 있던 값이 아니라 저장소를 다시 읽어 바꾸는 이유: 그 사이 백그라운드 작업이
  /// "도달함"이나 마지막 등락 알림 고시일을 기록했을 수 있다.
  Future<void> _update(String code, RateAlertSettings Function(RateAlertSettings) change) async {
    final store = ref.read(rateAlertStoreProvider);
    final scheduler = ref.read(rateAlertSchedulerProvider);
    await store.save(code, change(await store.read(code)));
    await scheduler.sync(enabled: await store.anyEnabled());
    if (mounted) ref.invalidate(rateAlertSettingsProvider(code));
  }

  Future<void> _setDaily(String code, bool on) async {
    if (on && !await _ensurePermission()) return;
    if (!mounted) return;
    await _update(code, (s) => s.copyWith(daily: on));
  }

  Future<void> _addTarget(String code, int unit, ExchangeRate rate) async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (amount == null || amount <= 0) {
      setState(() => _amountError = '금액을 확인해 주세요');
      return;
    }
    setState(() => _amountError = null);
    if (!await _ensurePermission() || !mounted) return;

    final now = DateTime.now();
    final target = RateTarget(
      id: newTargetId(now),
      unit: unit,
      targetKrw: amount,
      direction: _direction,
      active: true,
      createdAt: now,
    );
    await _update(code, (s) => s.copyWith(targets: [...s.targets, target]));
    if (!mounted) return;
    _amount.clear();
    if (isTargetReached(target, rate.krwRate)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('현재 환율이 이미 목표에 도달했어요')));
    }
  }

  /// 다시 켜면 도달 기록을 지워 처음부터 감시한다.
  Future<void> _toggleTarget(String code, int id, bool on) async {
    if (on && !await _ensurePermission()) return;
    if (!mounted) return;
    await _update(
      code,
      (s) => s.copyWith(targets: [
        for (final t in s.targets)
          if (t.id != id) t else if (on) t.copyWith(active: true, clearFiredAt: true) else t.copyWith(active: false),
      ]),
    );
  }

  Future<void> _deleteTarget(String code, int id) =>
      _update(code, (s) => s.copyWith(targets: [for (final t in s.targets) if (t.id != id) t]));
}

class _DailyRow extends StatelessWidget {
  const _DailyRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('매일 등락 알림', style: AppTextStyles.body),
              const SizedBox(height: 2),
              Text('새 고시 환율이 나오면 전 영업일 대비 등락을 알려줘요', style: AppTextStyles.caption),
            ],
          ),
        ),
        Switch(key: const Key('dailySwitch'), value: value, onChanged: onChanged),
      ],
    );
  }
}

/// 목표 한 줄. 꺼진 목표(도달했거나 사용자가 끔)는 회색으로 보인다.
class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.currency,
    required this.target,
    required this.onToggle,
    required this.onDelete,
  });

  final CurrencyInfo currency;
  final RateTarget target;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = target;
    final String status;
    if (t.active) {
      status = '대기 중';
    } else if (t.firedAt != null) {
      status = '도달 · ${formatMonthDay(t.firedAt!)}';
    } else {
      status = '꺼짐';
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${currency.unitLabel(t.unit)}당 ${formatTargetKrw(t.targetKrw)} ${t.direction.labelKo}',
                  style: AppTextStyles.body.copyWith(
                    color: t.active ? AppColors.ink : AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(status, style: AppTextStyles.caption),
              ],
            ),
          ),
          Switch(key: Key('targetSwitch_${t.id}'), value: t.active, onChanged: onToggle),
          IconButton(
            key: Key('deleteTarget_${t.id}'),
            icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SubPageHeader(title: title),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(message, style: AppTextStyles.caption, textAlign: TextAlign.center),
            ),
          ),
        ),
      ],
    );
  }
}
