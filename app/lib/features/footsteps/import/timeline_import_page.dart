import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/checkin.dart';
import '../providers/footsteps_providers.dart';
import 'timeline_import_parser.dart';

class TimelineImportPage extends ConsumerStatefulWidget {
  const TimelineImportPage({super.key});

  @override
  ConsumerState<TimelineImportPage> createState() => _TimelineImportPageState();
}

class _TimelineImportPageState extends ConsumerState<TimelineImportPage> {
  bool _importing = false;
  String? _resultMessage;

  Future<void> _pickAndImport() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    final path = files.isEmpty ? null : files.single.path;
    if (path == null) return;

    setState(() => _importing = true);

    final content = await File(path).readAsString();
    final points = parseTimelineExport(content);

    final repository = ref.read(footstepsRepositoryProvider);
    for (final point in points) {
      await repository.recordCheckinAt(point.lat, point.lng, point.timestamp, CheckinSource.import);
    }

    setState(() {
      _importing = false;
      _resultMessage = '${points.length}개 지점을 가져왔습니다.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timeline 가져오기')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Google 계정 설정 > 내 활동 데이터 다운로드(Takeout)에서 '
              'Timeline(위치 기록)을 JSON으로 내보낸 뒤 그 파일을 선택하세요. '
              '앱 설치 이전의 과거 기록을 채우는 용도입니다.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _importing ? null : _pickAndImport,
              child: Text(_importing ? '가져오는 중...' : 'JSON 파일 선택'),
            ),
            if (_resultMessage != null) ...[
              const SizedBox(height: 16),
              Text(_resultMessage!),
            ],
          ],
        ),
      ),
    );
  }
}
