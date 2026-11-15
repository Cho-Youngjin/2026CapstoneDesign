import 'dart:io';

import 'package:app/features/footsteps/lab/lab_sessions_panel.dart';
import 'package:app/features/footsteps/recording/recording_mode.dart';
import 'package:app/features/footsteps/recording/recording_providers.dart';
import 'package:app/features/footsteps/recording/session_library.dart';
import 'package:app/features/footsteps/recording/session_meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLibrary implements SessionLibrary {
  _FakeLibrary(this.sessions);

  final List<SessionSummary> sessions;
  int listCalls = 0;

  @override
  Future<List<SessionSummary>> list() async {
    listCalls++;
    return sessions;
  }

  @override
  Future<File> zip(SessionSummary session, Directory outDir) => throw UnimplementedError();
}

SessionSummary _summary(String id, {DateTime? endedAt, int errors = 0}) => SessionSummary(
      id: id,
      directory: Directory(id),
      sizeBytes: 12 * 1024 * 1024,
      meta: SessionMeta(
        sessionId: id,
        mode: RecordingMode.groundTruth,
        deviceModel: 'm',
        androidSdk: 35,
        appVersion: '1',
        startedAt: DateTime.utc(2026, 11, 9, 1),
        endedAt: endedAt,
        carryInitial: 'hand',
        errors: [
          for (var i = 0; i < errors; i++)
            SessionError(at: DateTime.utc(2026), source: 'gps', message: 'x'),
        ],
      ),
    );

void main() {
  testWidgets('세션마다 크기·기록 시간·오류 수를 보여 주고, 공유를 누르면 그 세션을 공유한다', (tester) async {
    final library = _FakeLibrary([
      _summary('20261110-090000-groundTruth'),
      _summary('20261109-080000-groundTruth', endedAt: DateTime.utc(2026, 11, 9, 2, 2), errors: 2),
    ]);
    final shared = <String>[];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionLibraryProvider.overrideWithValue(library),
        sessionSharerProvider.overrideWithValue((s) async => shared.add(s.id)),
      ],
      child: const MaterialApp(home: Scaffold(body: LabSessionsPanel(refreshToken: 0))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('20261110-090000-groundTruth'), findsOneWidget);
    expect(find.text('12.0MB · 기록 중이거나 비정상 종료 · 오류 0건'), findsOneWidget);
    expect(find.text('12.0MB · 62분 · 오류 2건'), findsOneWidget);

    await tester.tap(find.byKey(const Key('share-20261109-080000-groundTruth')));
    await tester.pumpAndSettle();
    expect(shared, ['20261109-080000-groundTruth']);
  });

  testWidgets('refreshToken이 바뀌면 목록을 다시 읽는다', (tester) async {
    final library = _FakeLibrary(const []);
    Widget panel(int token) => ProviderScope(
          overrides: [sessionLibraryProvider.overrideWithValue(library)],
          child: MaterialApp(home: Scaffold(body: LabSessionsPanel(refreshToken: token))),
        );

    await tester.pumpWidget(panel(0));
    await tester.pumpAndSettle();
    expect(find.text('저장된 세션이 없습니다.'), findsOneWidget);

    await tester.pumpWidget(panel(1));
    await tester.pumpAndSettle();
    expect(library.listCalls, 2);
  });
}
