import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/network/country_api.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/checkin.dart';
import '../health/distance_step_estimator.dart';
import '../providers/footsteps_providers.dart';
import 'base_google_map.dart';
import 'world_geojson_parser.dart';

final visitedCountriesProvider = FutureProvider<Set<String>>((ref) async {
  final checkins = await ref.watch(footstepsRepositoryProvider).allCheckins();
  return checkins
      .map((c) => c.countryIso)
      .where((iso) => iso != Checkin.unknownCountry)
      .toSet();
});

final cumulativeStepsProvider = FutureProvider<Map<String, int>>((ref) {
  return ref.watch(footstepsRepositoryProvider).cumulativeStepsByCountry();
});

/// Health Connect 걸음 수와는 독립적으로, 실시간 GPS 경로(RoutePoints)의 이동
/// 거리로부터 추정한 걸음 수. Health 연동이 잘 되는지 대조해보기 위한 검증용
/// 보조 지표라 화면에는 별도 표기로만 노출하고 "총 걸음"에는 합산하지 않는다.
final estimatedStepsByCountryProvider = FutureProvider<Map<String, int>>((ref) async {
  final repository = ref.watch(footstepsRepositoryProvider);
  final visited = await ref.watch(visitedCountriesProvider.future);

  final result = <String, int>{};
  for (final iso in visited) {
    final points = await repository.routePointsForCountry(iso);
    final latLngs = [for (final p in points) LatLng(p.lat, p.lng)];
    result[iso] = estimateStepsFromDistance(totalDistanceMeters(latLngs));
  }
  return result;
});

/// 상위 지도 — 세계지도에 방문국을 채색하고, 하단에 국가별 누적 걸음 카드를 보여준다.
/// 국가를 탭하면(지도 폴리곤 또는 하단 카드) [onCountryTap]을 호출해 하위 지도로 전환한다.
class WorldMapPage extends ConsumerWidget {
  const WorldMapPage({super.key, required this.onCountryTap});

  final void Function(String iso) onCountryTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final polygonsAsync = ref.watch(worldCountryPolygonsProvider);

    return polygonsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('지도를 불러오지 못했습니다\n$e', textAlign: TextAlign.center),
        ),
      ),
      data: (countryPolygons) => _WorldMapBody(
        countryPolygons: countryPolygons,
        onCountryTap: onCountryTap,
      ),
    );
  }
}

class _WorldMapBody extends ConsumerWidget {
  const _WorldMapBody({required this.countryPolygons, required this.onCountryTap});

  final List<CountryPolygon> countryPolygons;
  final void Function(String iso) onCountryTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visited = ref.watch(visitedCountriesProvider).asData?.value ?? const <String>{};
    final steps = ref.watch(cumulativeStepsProvider).asData?.value ?? const <String, int>{};
    final estimatedSteps =
        ref.watch(estimatedStepsByCountryProvider).asData?.value ?? const <String, int>{};
    final countries = ref.watch(countryListProvider).asData?.value ?? const <Country>[];
    final nameByIso = {for (final c in countries) c.isoAlpha2: c.nameKo};

    final mapPolygons = <Polygon>{};
    for (final country in countryPolygons) {
      final isVisited = visited.contains(country.isoAlpha2);
      for (var i = 0; i < country.rings.length; i++) {
        mapPolygons.add(Polygon(
          polygonId: PolygonId('${country.isoAlpha2}_$i'),
          points: country.rings[i],
          fillColor: isVisited
              ? AppColors.accent.withValues(alpha: 0.45)
              : AppColors.placeholderSecondary.withValues(alpha: 0.35),
          strokeColor: AppColors.borderLight,
          strokeWidth: 1,
          consumeTapEvents: true,
          onTap: () => onCountryTap(country.isoAlpha2),
        ));
      }
    }

    final visitedByStepsDesc = visited.toList()
      ..sort((a, b) => (steps[b] ?? 0).compareTo(steps[a] ?? 0));

    return Column(
      children: [
        SizedBox(
          height: 300,
          child: BaseGoogleMap(
            initialCamera: const CameraPosition(target: LatLng(20, 10), zoom: 1.3),
            polygons: mapPolygons,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '방문 국가 ${visitedByStepsDesc.length} · 총 걸음 ${steps.values.fold(0, (a, b) => a + b)}',
                style: AppTextStyles.caption,
              ),
              // Health Connect 연동 검증용 — GPS 이동 거리만으로 추정한 걸음 수.
              // 실제 걸음 수(위 줄)와 크게 어긋나면 Health 연동을 의심해볼 수 있다.
              Text(
                'GPS 거리 기준 추정 걸음 ${estimatedSteps.values.fold(0, (a, b) => a + b)} (테스트용)',
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Expanded(
          child: visitedByStepsDesc.isEmpty
              ? Center(
                  child: Text('아직 방문 기록이 없습니다', style: AppTextStyles.caption),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  itemCount: visitedByStepsDesc.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.dividerFaint),
                  itemBuilder: (context, i) {
                    final iso = visitedByStepsDesc[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(nameByIso[iso] ?? iso, style: AppTextStyles.body),
                      trailing: Text(
                        '${steps[iso] ?? 0}',
                        style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
                      ),
                      onTap: () => onCountryTap(iso),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
