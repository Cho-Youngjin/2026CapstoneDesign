import 'package:app/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/network/country_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import 'data/trip_api.dart';
import 'data/trip_providers.dart';

final _displayDate = DateFormat('yyyy-MM-dd');

/// 체류 일수. 서버 `VisaJudgementService`와 같은 방식(`DAYS.between`)으로 센다 —
/// 12/20 출발, 1/9 귀국이면 20일. 화면 숫자와 판정 기준이 어긋나지 않게 맞춘다.
int stayDaysBetween(DateTime depart, DateTime ret) =>
    DateTime.utc(ret.year, ret.month, ret.day)
        .difference(DateTime.utc(depart.year, depart.month, depart.day))
        .inDays;

/// 서버 오류를 사용자에게 보여줄 문장으로 바꾼다.
String tripErrorMessage(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 400) return '입력값을 다시 확인해 주세요.';
    if (status == 401) return '로그인이 만료됐어요. 다시 로그인해 주세요.';
    if (status == 404) return '선택한 국가의 정보를 찾을 수 없어요.';
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return '서버에 연결할 수 없어요. 네트워크를 확인해 주세요.';
    }
  }
  return '여행계획을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
}

/// 비자 탭의 기본 화면 — 여행 계획(목적지/일정) 입력 폼.
/// 와이어프레임: "해외여행 발걸음 - 와이어프레임" Plan B, 여행 계획 화면.
///
/// 제출하면 `POST /api/trips`로 비자 판정을 받고, 만들어진 여행을 활성 여행으로
/// 저장한 뒤 결과 화면으로 이동한다.
class VisaPage extends ConsumerStatefulWidget {
  const VisaPage({super.key});

  @override
  ConsumerState<VisaPage> createState() => _VisaPageState();
}

class _VisaPageState extends ConsumerState<VisaPage> {
  Country? _country;
  DateTime? _departDate;
  DateTime? _returnDate;
  DateTime? _passportExpiry;
  bool _submitting = false;
  String? _error;

  bool get _datesInOrder =>
      _departDate == null ||
      _returnDate == null ||
      !_returnDate!.isBefore(_departDate!);

  bool get _canSubmit =>
      _country != null &&
      _departDate != null &&
      _returnDate != null &&
      _passportExpiry != null &&
      _datesInOrder &&
      !_submitting;

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<Country>(
      context: context,
      builder: (_) => const _CountryPickerSheet(),
    );
    if (picked != null) setState(() => _country = picked);
  }

  Future<DateTime?> _pickDate({
    required DateTime? current,
    required DateTime first,
    required DateTime last,
  }) {
    final initial = current ?? first;
    return showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: last,
    );
  }

  Future<void> _pickDepartDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await _pickDate(
      current: _departDate,
      first: today,
      last: today.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _departDate = picked);
  }

  Future<void> _pickReturnDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final first = _departDate ?? today;
    final picked = await _pickDate(
      current: _returnDate,
      first: first,
      last: first.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _returnDate = picked);
  }

  Future<void> _pickPassportExpiry() async {
    final today = DateUtils.dateOnly(DateTime.now());
    // 이미 만료된 여권도 입력할 수 있어야 한다 — 그래야 "재발급 필요" 판정을 받는다.
    final picked = await _pickDate(
      current: _passportExpiry,
      first: today.subtract(const Duration(days: 365 * 5)),
      last: today.add(const Duration(days: 365 * 11)),
    );
    if (picked != null) setState(() => _passportExpiry = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final trip = await ref.read(tripApiProvider).createTrip(
            countryIso2: _country!.isoAlpha2,
            departDate: _departDate!,
            returnDate: _returnDate!,
            passportExpiry: _passportExpiry!,
          );
      await ref.read(activeTripIdProvider.notifier).set(trip.id);
      if (mounted) context.push(AppRoutes.visaResult);
    } catch (e) {
      if (mounted) setState(() => _error = tripErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.borderLight),
            ),
          ),
          child: Text('여행 계획', style: AppTextStyles.screenTitle),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FieldGroup(
                  label: '목적지 국가',
                  child: _CountryBox(
                    key: const Key('countryField'),
                    country: _country,
                    onTap: _submitting ? null : _pickCountry,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _FieldGroup(
                        label: '출발일',
                        child: _DateBox(
                          key: const Key('departDateField'),
                          value: _departDate,
                          onTap: _submitting ? null : _pickDepartDate,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FieldGroup(
                        label: '귀국일',
                        child: _DateBox(
                          key: const Key('returnDateField'),
                          value: _returnDate,
                          onTap: _submitting ? null : _pickReturnDate,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _FieldGroup(
                  label: '여권 만료일',
                  child: _DateBox(
                    key: const Key('passportExpiryField'),
                    value: _passportExpiry,
                    onTap: _submitting ? null : _pickPassportExpiry,
                  ),
                ),
                const SizedBox(height: 18),
                _StaySummary(
                  departDate: _departDate,
                  returnDate: _returnDate,
                ),
                const SizedBox(height: 18),
                Text('최근 검색', style: AppTextStyles.label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterPill(label: '일본', selected: false, onTap: () {}),
                    FilterPill(label: '태국', selected: false, onTap: () {}),
                    FilterPill(label: '프랑스', selected: false, onTap: () {}),
                  ],
                ),
                const SizedBox(height: 32),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      key: const Key('tripFormError'),
                      style: AppTextStyles.caption.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                PillButton(
                  key: const Key('submitTripButton'),
                  label: _submitting ? '판정 중…' : '비자 판정하기',
                  height: 50,
                  onPressed: _canSubmit ? _submit : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 체류 일수 요약. 날짜가 덜 골라졌거나 순서가 뒤바뀌면 안내 문구를 보여준다.
class _StaySummary extends StatelessWidget {
  const _StaySummary({required this.departDate, required this.returnDate});

  final DateTime? departDate;
  final DateTime? returnDate;

  @override
  Widget build(BuildContext context) {
    final String text;
    var isError = false;
    if (departDate == null || returnDate == null) {
      text = '출발일과 귀국일을 선택하세요';
    } else if (returnDate!.isBefore(departDate!)) {
      text = '귀국일이 출발일보다 빨라요';
      isError = true;
    } else {
      text = '체류 ${stayDaysBetween(departDate!, returnDate!)}일';
    }

    return Container(
      key: const Key('staySummary'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: AppTextStyles.chip.copyWith(
          color: isError
              ? Theme.of(context).colorScheme.error
              : AppColors.textBody,
        ),
      ),
    );
  }
}

/// 서버의 국가 목록(`/api/countries`)을 바텀시트로 보여주고, 고른 국가를 pop으로 돌려준다.
/// 시트를 열 때 처음 불러오므로 화면 진입만으로는 서버를 호출하지 않는다.
class _CountryPickerSheet extends ConsumerWidget {
  const _CountryPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countries = ref.watch(countryListProvider);
    return SafeArea(
      child: SizedBox(
        height: 360,
        child: countries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('국가 목록을 불러오지 못했어요'),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => ref.invalidate(countryListProvider),
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            ),
          ),
          data: (list) => ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => ListTile(
              title: Text(list[i].nameKo),
              subtitle: Text(list[i].nameEn ?? '-'),
              trailing: Text('Tier ${list[i].tier}'),
              onTap: () => Navigator.of(context).pop(list[i]),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldGroup extends StatelessWidget {
  const _FieldGroup({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// 입력칸 공통 테두리. 와이어프레임의 52px 박스 모양을 유지한다.
class _InputBox extends StatelessWidget {
  const _InputBox({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 52,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderMedium),
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}

class _CountryBox extends StatelessWidget {
  const _CountryBox({super.key, required this.country, required this.onTap});

  final Country? country;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final selected = country;
    return _InputBox(
      onTap: onTap,
      child: Row(
        children: [
          const SizedBox(
            width: 26,
            height: 18,
            child: WireframePlaceholder(borderRadius: 3),
          ),
          const SizedBox(width: 10),
          if (selected == null)
            Text(
              '국가를 선택하세요',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else ...[
            Text(selected.nameKo, style: AppTextStyles.body),
            const SizedBox(width: 10),
            Text(
              '${selected.isoAlpha2} · Tier ${selected.tier}',
              style: AppTextStyles.caption,
            ),
          ],
          const Spacer(),
          Text('▾', style: AppTextStyles.caption.copyWith(fontSize: 14)),
        ],
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({super.key, required this.value, required this.onTap});

  final DateTime? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final date = value;
    return _InputBox(
      onTap: onTap,
      child: Text(
        date == null ? '선택' : _displayDate.format(date),
        style: date == null
            ? AppTextStyles.body.copyWith(color: AppColors.textSecondary)
            : AppTextStyles.body,
      ),
    );
  }
}
