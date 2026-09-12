import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/country_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';

/// 준비물 · 베트남 — 짐/서류 체크리스트 와이어프레임 화면.
///
/// UI 전용 정적 화면이다. 실제 API 연동/영속화는 이후 마일스톤에서 다룬다.
/// 모든 카피는 와이어프레임의 placeholder 값을 그대로 옮긴 것이다.
class ChecklistPage extends StatefulWidget {
  const ChecklistPage({super.key});

  @override
  State<ChecklistPage> createState() => _ChecklistPageState();
}

class _ChecklistPageState extends State<ChecklistPage> {
  final Map<String, bool> _documentChecks = {
    '여권 사본': true,
    '여행자보험 증서': true,
    '_doc_placeholder_3': false,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Header(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CountryInfoRow(),
                const SizedBox(height: 14),
                _ProgressCard(),
                const SizedBox(height: 14),
                const SectionLabel('서류'),
                const SizedBox(height: 4),
                _ChecklistRow(
                  checked: _documentChecks['여권 사본']!,
                  label: '여권 사본',
                  onTap: () => setState(
                    () => _documentChecks['여권 사본'] =
                        !_documentChecks['여권 사본']!,
                  ),
                ),
                _ChecklistRow(
                  checked: _documentChecks['여행자보험 증서']!,
                  label: '여행자보험 증서',
                  onTap: () => setState(
                    () => _documentChecks['여행자보험 증서'] =
                        !_documentChecks['여행자보험 증서']!,
                  ),
                ),
                _PlaceholderItemRow(
                  checked: _documentChecks['_doc_placeholder_3']!,
                  onTap: () => setState(
                    () => _documentChecks['_doc_placeholder_3'] =
                        !_documentChecks['_doc_placeholder_3']!,
                  ),
                  barWidthFactor1: 0.58,
                  barWidthFactor2: 0.78,
                ),
                const SizedBox(height: 14),
                const SectionLabel('전자기기'),
                const SizedBox(height: 4),
                const _PlaceholderItemRow(
                  checked: false,
                  barWidthFactor1: 0.44,
                  barWidthFactor2: 0.66,
                ),
                const _PlaceholderItemRow(
                  checked: false,
                  barWidthFactor1: 0.52,
                  barWidthFactor2: 0.40,
                ),
                const _PlaceholderItemRow(
                  checked: false,
                  barWidthFactor1: 0.36,
                  barWidthFactor2: null,
                ),
                const SizedBox(height: 14),
                const _AddManuallyRow(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('준비물 · 베트남', style: AppTextStyles.screenTitle),
          GestureDetector(
            onTap: () => _showCountryPicker(context),
            child: Text(
              '국가 변경',
              style: AppTextStyles.caption.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// 서버의 국가 목록(`/api/countries`)을 불러와 바텀시트로 보여준다.
/// 국가별 준비물 데이터 연동은 이후 마일스톤에서 다룬다 — 지금은 목록 선택만 된다.
void _showCountryPicker(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: SizedBox(
        height: 360,
        child: Consumer(
          builder: (context, ref, _) {
            final countries = ref.watch(countryListProvider);
            return countries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('국가 목록을 불러오지 못했습니다\n$e', textAlign: TextAlign.center),
                ),
              ),
              data: (list) => ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => ListTile(
                  title: Text(list[i].nameKo),
                  subtitle: Text(list[i].nameEn ?? '-'),
                  trailing: Text('Tier ${list[i].tier}'),
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _CountryInfoRow extends StatelessWidget {
  const _CountryInfoRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: _CountryInfoCard(label: '플러그', value: 'C형 220V')),
        SizedBox(width: 8),
        Expanded(child: _CountryInfoCard(label: '결제', value: '현금 권장')),
        SizedBox(width: 8),
        Expanded(child: _CountryInfoCard(label: '보조배터리', value: '100Wh')),
      ],
    );
  }
}

class _CountryInfoCard extends StatelessWidget {
  const _CountryInfoCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.placeholderPrimary,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: AppTextStyles.caption),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Noto Sans KR',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('진행률', style: AppTextStyles.chip),
              const Text(
                '8 / 14',
                style: TextStyle(
                  fontFamily: 'Noto Sans KR',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.placeholderSecondary,
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.57,
                child: Container(color: AppColors.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 완료/미완료 상태를 표현하는 실제 서류 항목 행 (탭하면 토글).
class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.checked,
    required this.label,
    this.onTap,
  });

  final bool checked;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
        ),
        child: Row(
          children: [
            _CheckboxSquare(checked: checked),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Noto Sans KR',
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  color: checked
                      ? AppColors.textTertiary
                      : AppColors.textBody,
                  decoration: checked
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 이름이 아직 placeholder 막대인 항목 행(전자기기 섹션 등).
class _PlaceholderItemRow extends StatelessWidget {
  const _PlaceholderItemRow({
    required this.checked,
    required this.barWidthFactor1,
    required this.barWidthFactor2,
    this.onTap,
  });

  final bool checked;
  final double barWidthFactor1;
  final double? barWidthFactor2;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
        ),
        child: Row(
          children: [
            _CheckboxSquare(checked: checked),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: barWidthFactor1,
                    child: Container(
                      height: 11,
                      decoration: BoxDecoration(
                        color: AppColors.placeholderPrimary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  if (barWidthFactor2 != null) ...[
                    const SizedBox(height: 6),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: barWidthFactor2,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.placeholderSecondary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckboxSquare extends StatelessWidget {
  const _CheckboxSquare({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    if (!checked) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.placeholderPrimary, width: 1.5),
          borderRadius: BorderRadius.circular(5),
        ),
      );
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Icon(Icons.check, size: 14, color: Colors.white),
    );
  }
}

class _AddManuallyRow extends StatelessWidget {
  const _AddManuallyRow();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderMedium),
          borderRadius: BorderRadius.circular(980),
        ),
        child: Text(
          '+ 직접 추가',
          style: AppTextStyles.chip.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
