import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/country_api.dart';
import 'api/embassy_api.dart';
import 'api/places_api.dart';
import 'api/travel_alert_api.dart';
import 'models/embassy.dart';
import 'models/travel_alert.dart';
import 'providers/nearby_selection_providers.dart';
import 'widgets/alert_badge.dart';
import 'widgets/category_filter_tabs.dart';
import 'widgets/embassy_card.dart';
import 'widgets/nearby_map_view.dart';
import 'widgets/place_list_tile.dart';

class NearbyPage extends ConsumerWidget {
  const NearbyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(currentPositionProvider);
    final countries = ref.watch(countryListProvider);
    final selectedIso2 = ref.watch(selectedCountryProvider);
    final currentLocationIso2 = ref.watch(currentLocationCountryProvider).asData?.value;

    // 사용자가 직접 고른 국가 > 현재 위치가 속한 국가 > 국가 목록의 첫 항목 순.
    // 마지막 fallback은 위치 판정이 아직 끝나지 않았거나 실패했을 때만 쓰인다.
    String? effectiveIso2(List<Country> list) =>
        selectedIso2 ?? currentLocationIso2 ?? (list.isEmpty ? null : list.first.isoAlpha2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('주변'),
        actions: [
          IconButton(
            tooltip: '위치 새로고침',
            icon: const Icon(Icons.my_location),
            onPressed: () => ref.invalidate(currentPositionProvider),
          ),
          countries.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              final effective = effectiveIso2(list)!;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: DropdownButton<String>(
                  value: effective,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final c in list)
                      DropdownMenuItem(value: c.isoAlpha2, child: Text(c.nameKo)),
                  ],
                  onChanged: (value) =>
                      ref.read(selectedCountryProvider.notifier).state = value,
                ),
              );
            },
          ),
        ],
      ),
      body: position.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '현재 위치를 가져오지 못했습니다\n위치 권한을 확인해 주세요',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (pos) {
          // 국가 목록이 아직 없으면(로딩·에러 중) iso2 관련 조회는 전부 건너뛴다.
          final iso2 = effectiveIso2(countries.asData?.value ?? const []);

          final places = ref.watch(nearbyPlacesProvider);
          final AsyncValue<List<TravelAlert>> alerts = iso2 == null
              ? const AsyncValue.data([])
              : ref.watch(travelAlertsProvider(iso2));
          final AsyncValue<List<Embassy>> embassies = iso2 == null
              ? const AsyncValue.data([])
              : ref.watch(embassiesProvider(iso2));

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 240,
                  child: NearbyMapView(
                    center: pos,
                    places: places.asData?.value ?? const [],
                    embassies: embassies.asData?.value ?? const [],
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CategoryFilterTabs(),
                ),
              ),
              if ((alerts.asData?.value ?? const []).isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final a in alerts.asData!.value) AlertBadge(level: a.level),
                      ],
                    ),
                  ),
                ),
              places.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('주변 정보를 불러오지 못했습니다\n$e'),
                  ),
                ),
                data: (list) => SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => PlaceListTile(place: list[i]),
                ),
              ),
              if ((embassies.asData?.value ?? const []).isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      '재외공관',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: embassies.asData!.value.length,
                  itemBuilder: (context, i) =>
                      EmbassyCard(embassy: embassies.asData!.value[i]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
