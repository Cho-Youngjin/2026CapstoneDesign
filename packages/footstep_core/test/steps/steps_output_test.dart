import 'dart:convert';
import 'dart:io';

import 'package:footstep_core/footstep_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

MarkReading mark(int tMs, String kind, [String value = '']) =>
    MarkReading(tMs: tMs, kind: kind, value: value);

void main() {
  final marks = [
    mark(1000, MarkReading.countStart),
    mark(11000, MarkReading.countEnd, '10'),
    mark(12000, MarkReading.countStart),
    mark(15000, MarkReading.countEnd), // 센 수를 안 적었다
    mark(20000, MarkReading.board, 'bus'),
    mark(30000, MarkReading.alight),
    mark(40000, MarkReading.board, 'subway'), // 내리기 전에 세션이 끝났다
  ];
  const steps = [500, 1000, 5000, 11000, 12500, 25000];

  test('걸음 세기 구간은 count_start~count_end(양 끝 포함)이고, 센 수가 있으면 오차(%)를 낸다', () {
    final intervals = countIntervals(marks, steps);

    expect(intervals.map((c) => (c.startMs, c.endMs, c.manualSteps, c.detectedSteps)), [
      (1000, 11000, 10, 3),
      (12000, 15000, null, 1),
    ]);
    expect(intervals.first.errorPct, closeTo(-70.0, 1e-9));
    expect(intervals.last.errorPct, isNull);
  });

  test('탈것 구간은 board~alight이고, 내리지 않은 탑승은 넣지 않는다', () {
    final intervals = vehicleIntervals(marks, steps);
    expect(intervals.map((v) => (v.boardMs, v.alightMs, v.kind, v.detectedSteps)),
        [(20000, 30000, 'bus', 1)]);
  });

  test('steps.csv·step_states.csv·step_summary.json을 쓴다', () async {
    final root = await Directory.systemTemp.createTemp('steps_output_test');
    addTearDown(() => root.delete(recursive: true));
    const run = StepRun(
      sessionId: 's1',
      detectorId: 'adaptive',
      detectorParams: {'n_confirm': 5},
      startMs: 0,
      endMs: 40000,
      stepTimes: steps,
      states: [
        StateChange(tMs: 2000, state: StepState.still),
        StateChange(tMs: 10000, state: StepState.walking, cadenceHz: 2.0),
      ],
    );
    final out = Directory(p.join(root.path, 'nested', 'out'));

    await writeStepsOutput(run, marks, out);

    expect(File(p.join(out.path, StepsSchema.stepsFile)).readAsLinesSync(),
        ['t_ms,total_steps', '500,1', '1000,2', '5000,3', '11000,4', '12500,5', '25000,6']);
    expect(File(p.join(out.path, StepsSchema.statesFile)).readAsLinesSync(),
        ['t_ms,state,cadence_hz', '2000,still,', '10000,walking,2.0']);
    final summary = jsonDecode(File(p.join(out.path, StepsSchema.summaryFile)).readAsStringSync())
        as Map<String, Object?>;
    expect(summary['detector_id'], 'adaptive');
    expect(summary['detector_params'], {'n_confirm': 5});
    expect(summary['total_steps'], 6);
    expect(summary['state_seconds'],
        {'unknown': 2.0, 'still': 8.0, 'walking': 30.0, 'otherMotion': 0.0});
    expect((summary['count_intervals'] as List).first,
        {'start_ms': 1000, 'end_ms': 11000, 'manual_steps': 10, 'detected_steps': 3, 'error_pct': -70.0});
    expect((summary['vehicle_intervals'] as List).single,
        {'board_ms': 20000, 'alight_ms': 30000, 'kind': 'bus', 'detected_steps': 1});
  });
}
