import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/country_api.dart';
import 'api/embassy_api.dart';
import 'api/places_api.dart';
import 'api/travel_alert_api.dart';
import 'models/embassy.dart';
import 'models/travel_alert.dart';
import '../footsteps/providers/footsteps_providers.dart' show overseasPositionProvider;
import '../footsteps/providers/overseas_mapping_session.dart' show overseasMappingProvider;
import 'providers/nearby_selection_providers.dart';
import 'widgets/alert_section.dart';
import 'widgets/category_filter_tabs.dart';
import 'widgets/embassy_card.dart';
import 'widgets/nearby_map_view.dart';
import 'widgets/place_list_tile.dart';

class NearbyPage extends ConsumerStatefulWidget {
  const NearbyPage({super.key});

  @override
  ConsumerState<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends ConsumerState<NearbyPage> {
  @override
  void initState() {
    super.initState();
    // 탭에 들어올 때마다 최신 위치로 새로고침한다(해외 매핑 중이면 해외 현재 위치).
    // 위치 권한 거부 등으로 실패해도 화면은 아래 position.when의 에러 표시로 처리한다.
    Future.microtask(() async {
      try {
        await refreshNearbyPosition(ref);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(nearbyPositionProvider);
    final countries = ref.watch(countriesWithHomeProvider);
    final selectedIso2 = ref.watch(selectedCountryProvider);
    final currentLocationIso2 = ref.watch(currentLocationCountryProvider).asData?.value;

    // 사용자가 직접 고른 국가 > 현재 위치가 속한 국가 > 국가 목록의 첫 항목 순.
    // 목록에 없는 값은 건너뛴다 — 자세한 이유는 effectiveCountryIso2 주석 참고.
    String? effectiveIso2(List<Country> list) => effectiveCountryIso2(
          selected: selectedIso2,
          currentLocation: currentLocationIso2,
          available: [for (final c in list) c.isoAlpha2],
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('주변'),
        actions: [
          IconButton(
            tooltip: '위치 새로고침',
            icon: const Icon(Icons.my_location),
            onPressed: () => refreshNearbyPosition(ref),
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
          // 국가가 아직 정해지지 않았으면(null) "경보 없음"이라고 말하지 않도록 구분해 둔다.
          // 본국(한국)은 서버 국가 목록에 없어 경보·공관 API가 404다 — 부르지 않고 "경보 없음"이라고도
          // 말하지 않는다(null).
          final isAbroad = iso2 != null && iso2 != homeCountryIso2;
          final AsyncValue<List<TravelAlert>>? alerts =
              isAbroad ? ref.watch(travelAlertsProvider(iso2)) : null;
          final AsyncValue<List<Embassy>> embassies = isAbroad
              ? ref.watch(embassiesProvider(iso2))
              : const AsyncValue.data([]);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 240,
                  child: NearbyMapView(
                    center: pos,
                    places: places.asData?.value ?? const [],
                    embassies: embassies.asData?.value ?? const [],
                    overseasPosition: ref.watch(overseasPositionProvider),
                    overseasHeading: ref.watch(overseasMappingProvider.select((s) => s.jpHeading)),
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CategoryFilterTabs(),
                ),
              ),
              SliverToBoxAdapter(child: AlertSection(alerts: alerts)),
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
