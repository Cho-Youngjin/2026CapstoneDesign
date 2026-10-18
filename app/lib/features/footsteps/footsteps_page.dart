import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'background/background_location_permission.dart';
import 'background/battery_optimization.dart';
import 'import/timeline_import_page.dart';
import 'map/country_detail_map_page.dart';
import 'map/overseas_anchor_picker_dialog.dart';
import 'map/overseas_mapping_page.dart';
import 'map/world_map_page.dart';
import 'providers/footsteps_providers.dart';
import 'providers/overseas_mapping_session.dart';

/// 해외 매핑 대상국(설계 문서 §2, 2026-09-29 확정).
const _overseasMappingCountry = 'JP';
// 간토 지역(도쿄) 중심 — 해외 출발 좌표 선택 팝업의 초기 카메라 위치.
const _overseasMappingInitialCamera = CameraPosition(target: LatLng(35.6762, 139.6503), zoom: 12);

/// 발걸음 탭의 최종 화면. 상위(세계지도)/하위(국가 상세) 지도를 내부 상태로 전환한다
/// (go_router 라우트 추가 없음).
class FootstepsPage extends ConsumerStatefulWidget {
  const FootstepsPage({super.key});

  @override
  ConsumerState<FootstepsPage> createState() => _FootstepsPageState();
}

class _FootstepsPageState extends ConsumerState<FootstepsPage> {
  String? _selectedCountryIso;
  bool _batteryPromptShown = false;

  @override
  void initState() {
    super.initState();
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
          // "항상 허용"을 먼저 받는다 — 이게 없으면 1시간 주기 자동 체크인이
          // 백그라운드에서 위치를 못 읽어 조용히 아무것도 기록하지 않는다.
          await requestBackgroundLocation();
          await requestIgnoreBatteryOptimization();
        } catch (_) {}
      }
    });
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

  // 임포트는 체크인 행을 새로 넣으므로, 돌아올 때 지도 데이터를 다시 읽어야 한다 —
  // 그냥 push만 하면 캐시된 방문국 목록이 그대로 남아 새 국가가 세계지도에 안 뜬다.
  Future<void> _openTimelineImport() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TimelineImportPage()),
    );
    if (mounted) _refreshMapData();
  }

  // 해외 매핑(설계 문서 §9) — 팝업에서 해외 출발 좌표를 고르고 검증까지 통과하면 해외 매핑
  // 세션을 시작한다. 세션이 켜져 있는 동안 이 탭은 해외 매핑 화면을 보여준다.
  Future<void> _openOverseasMapping() async {
    final anchor = await showDialog<LatLng>(
      context: context,
      builder: (_) => const OverseasAnchorPickerDialog(
        country: _overseasMappingCountry,
        initialCamera: _overseasMappingInitialCamera,
      ),
    );
    if (anchor == null || !mounted) return;

    ref.read(overseasMappingProvider.notifier).start(_overseasMappingCountry, anchor);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(overseasMappingProvider.select((s) => s.active))) {
      return const OverseasMappingPage();
    }

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
            onPressed: _openTimelineImport,
            child: const Icon(Icons.file_upload_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'overseas_mapping_test',
            onPressed: _openOverseasMapping,
            icon: const Icon(Icons.travel_explore),
            label: const Text('해외 매핑'),
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
