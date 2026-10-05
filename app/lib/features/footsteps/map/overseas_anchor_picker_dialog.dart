import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/network/api_client.dart';
import '../data/overseas_mapping_api.dart';
import 'base_google_map.dart';

/// 해외 매핑 테스트(설계 문서 §9)의 해외 출발 좌표 선택 팝업. 지도를 탭해
/// 후보 지점을 고르고 [동작]을 누르면, 서버에 도로 근접 여부를 검증한
/// 뒤에만 닫힌다 — 도로가 없는 지점(바다·건물 한가운데)은 여기서 걸러
/// 재선택을 요구한다(설계 문서 §4(5)).
///
/// 성공 시 선택 지점을 도로 위로 붙인 [LatLng]을 반환하며 닫힌다.
class OverseasAnchorPickerDialog extends ConsumerStatefulWidget {
  const OverseasAnchorPickerDialog({
    super.key,
    required this.country,
    required this.initialCamera,
  });

  final String country;
  final CameraPosition initialCamera;

  @override
  ConsumerState<OverseasAnchorPickerDialog> createState() =>
      _OverseasAnchorPickerDialogState();
}

class _OverseasAnchorPickerDialogState extends ConsumerState<OverseasAnchorPickerDialog> {
  LatLng? _candidate;
  bool _validating = false;
  String? _error;

  Future<void> _onStart() async {
    final candidate = _candidate;
    if (candidate == null) {
      setState(() => _error = '지도를 탭해 출발 지점을 선택하세요');
      return;
    }

    setState(() {
      _validating = true;
      _error = null;
    });

    try {
      final snapped =
          await validateOverseasAnchor(ref.read(apiClientProvider), widget.country, candidate);
      if (!mounted) return;
      if (snapped == null) {
        setState(() {
          _validating = false;
          _error = '도로 근처가 아닙니다. 다른 지점을 선택하세요';
        });
        return;
      }
      Navigator.of(context).pop(snapped);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _validating = false;
        _error = '검증 실패: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.maxFinite,
        height: 480,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('해외 출발 지점 선택', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: BaseGoogleMap(
                initialCamera: widget.initialCamera,
                markers: _candidate == null
                    ? const {}
                    : {Marker(markerId: const MarkerId('anchor_candidate'), position: _candidate!)},
                onTap: (point) => setState(() {
                  _candidate = point;
                  _error = null;
                }),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _validating ? null : () => Navigator.of(context).pop(),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _validating ? null : _onStart,
                    child: _validating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('동작'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
