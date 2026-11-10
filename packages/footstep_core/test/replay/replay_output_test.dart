import 'dart:convert';
import 'dart:io';

import 'package:footstep_core/footstep_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('replay_output_test'));
  tearDown(() async => root.delete(recursive: true));

  test('fixes.csv·actions.csv·summary.json을 설계 문서 5-4 형식으로 쓴다', () async {
    const fix = Fix(tMs: 1000, lat: 37.5665, lng: 126.978, accuracyM: 4.5);
    const result = ReplayResult(
      fixes: [FixRecord(fix: fix, stepsSincePrev: 12, state: 'walking', kind: 'single')],
      actions: [
        ActionRecord(tMs: 0, action: RequestFix()),
        ActionRecord(tMs: 0, action: WakeAt(tMs: 60000, tag: 'tick')),
      ],
      summary: ReplaySummary(
        sessionId: 's1',
        policyId: 'fixed_1m',
        policyParams: {'interval_s': 60},
        detectorId: 'os',
        ttffMs: 0,
        startMs: 0,
        endMs: 120000,
        fixRequests: 1,
        fixSuccesses: 1,
        fixFailures: 0,
        continuousFixes: 0,
        gpsOnMs: 1000,
      ),
    );
    final out = Directory(p.join(root.path, 'nested', 'out'));

    await writeReplayOutput(result, out);

    expect(File(p.join(out.path, 'fixes.csv')).readAsLinesSync(), [
      't_ms,lat,lng,accuracy_m,steps_since_prev,state,kind',
      '1000,37.5665,126.978,4.5,12,walking,single',
    ]);
    expect(File(p.join(out.path, 'actions.csv')).readAsLinesSync(), [
      't_ms,action,args',
      '0,request_fix,timeout_ms=15000',
      '0,wake_at,t_ms=60000 tag=tick',
    ]);
    final summary =
        jsonDecode(File(p.join(out.path, 'summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect(summary['policy_id'], 'fixed_1m');
    expect(summary['total_fixes'], 1);
    expect(summary['gps_on_s'], 1.0);
  });
}
