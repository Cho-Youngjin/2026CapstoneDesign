import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'background/battery_optimization.dart';
import 'import/timeline_import_page.dart';
import 'map/country_detail_map_page.dart';
import 'map/overseas_anchor_picker_dialog.dart';
import 'map/overseas_mapping_test_page.dart';
import 'map/world_map_page.dart';
import 'providers/footsteps_providers.dart';

/// 해외 매핑 테스트 데모 대상국(설계 문서 §2, 2026-09-29 확정).
const _overseasMappingTestCountry = 'JP';
// 간토 지역(도쿄) 중심 — 해외 출발 좌표 선택 팝업의 초기 카메라 위치.
const _overseasMappingTestInitialCamera = CameraPosition(target: LatLng(35.6762, 139.6503), zoom: 12);

/// 발걸음 탭의 최종 화면. 상위(세계지도)/하위(국가 상세) 지도를 내부 상태로 전환한다
/// (go_router 라우트 추가 없음).
class FootstepsPage extends ConsumerStatefulWidget {
  const FootstepsPage({super.key});

  @override
  ConsumerState<FootstepsPage> createState() => _FootstepsPageState();
}

class _FootstepsPageState extends ConsumerState<FootstepsPage> with WidgetsBindingObserver {
  String? _selectedCountryIso;
  bool _batteryPromptShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 화면 진입 시 최신 상태로 동기화한다. 실패해도 조용히 무시한다 —
    // 오프라인이어도 로컬 기록·조회는 계속 동작해야 한다.
    Future.microtask(() async {
      try {
        await runFootstepsSync(ref);
        if (mounted) _refreshMapData();
      } catch (_) {}

      // 로그인 직후가 아니라 발걸음 탭 첫 진입 시 1회 요청한다 — 앱 시작 직후 띄우면
      // 로그인 화면 위에 겹쳐 UX가 나빠진다. 배터리 최적화 요청은 부가 기능이라
      // 플랫폼 채널이 실패해도(권한 플러그인 미지원 기기 등) 화면 진입을 막지 않는다.
      if (!_batteryPromptShown && mounted) {
        _batteryPromptShown = true;
        try {
          await requestIgnoreBatteryOptimization();
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 화면이 떠 있어도 앱이 백그라운드로 가면(홈 버튼, 다른 앱 전환) GPS 스트림을
  // 끊는다 — 실시간 추적을 "발걸음 탭을 보고 있는 동안"으로 한정해 배터리를
  // 방어하려는 설계다. 다시 앱을 열면 자동으로 재개된다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(realtimeTrackingEnabledProvider.notifier).state =
        state == AppLifecycleState.resumed;
  }

  Future<void> _recordManualCheckin() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(footstepsRepositoryProvider).recordManualCheckin();
      messenger.showSnackBar(const SnackBar(content: Text('현재 위치를 저장했습니다')));
      _refreshMapData();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
  }

  // visitedCountriesProvider/cumulativeStepsProvider는 FutureProvider라 한 번 계산되면
  // 캐시된다 — setState만으로는 재실행되지 않으므로 명시적으로 invalidate해야 한다.
  void _refreshMapData() {
    ref.invalidate(visitedCountriesProvider);
    ref.invalidate(cumulativeStepsProvider);
  }

  // 검증용 도구(설계 문서 §9) — 팝업에서 해외 출발 좌표를 고르고 검증까지
  // 통과하면, 좌/우 분할 화면으로 넘어가 실시간 매핑을 보여준다. 여기서 만든
  // 경로는 체크인/RoutePoint로 저장되지 않는다.
  Future<void> _openOverseasMappingTest() async {
    final anchor = await showDialog<LatLng>(
      context: context,
      builder: (_) => const OverseasAnchorPickerDialog(
        country: _overseasMappingTestCountry,
        initialCamera: _overseasMappingTestInitialCamera,
      ),
    );
    if (anchor == null || !mounted) return;

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OverseasMappingTestPage(
        country: _overseasMappingTestCountry,
        initialAnchor: anchor,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedCountryIso != null) {
      return CountryDetailMapPage(
        isoAlpha2: _selectedCountryIso!,
        onBack: () => setState(() => _selectedCountryIso = null),
      );
    }

    return Scaffold(
      body: WorldMapPage(
        onCountryTap: (iso) => setState(() => _selectedCountryIso = iso),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'timeline_import',
            tooltip: 'Timeline 가져오기',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TimelineImportPage()),
            ),
            child: const Icon(Icons.file_upload_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'overseas_mapping_test',
            onPressed: _openOverseasMappingTest,
            icon: const Icon(Icons.travel_explore),
            label: const Text('해외 매핑 테스트'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'manual_checkin',
            onPressed: _recordManualCheckin,
            icon: const Icon(Icons.my_location),
            label: const Text('여기 저장'),
          ),
        ],
      ),
    );
  }
}
