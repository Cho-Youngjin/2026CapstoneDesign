import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../events/policy_event.dart';
import '../model/readings.dart';
import '../session/csv.dart';
import 'step_run.dart';

/// 걸음 감지 결과 파일 이름과 헤더. R6 분석이 같은 이름을 읽는다.
abstract final class StepsSchema {
  static const stepsFile = 'steps.csv';
  static const stepsHeader = ['t_ms', 'total_steps'];
  static const statesFile = 'step_states.csv';
  static const statesHeader = ['t_ms', 'state', 'cadence_hz'];
  static const summaryFile = 'step_summary.json';
}

/// 걸음 세기 구간 하나(count_start~count_end, 양 끝 포함)와 직접 센 걸음 수.
class CountInterval {
  const CountInterval({
    required this.startMs,
    required this.endMs,
    required this.manualSteps,
    required this.detectedSteps,
  });

  final int startMs;
  final int endMs;

  /// count_end에 적은 수. 안 적었으면 null이다.
  final int? manualSteps;
  final int detectedSteps;

  /// (감지 − 직접 센 수) ÷ 직접 센 수 × 100. 센 수가 없거나 0이면 null이다.
  double? get errorPct {
    final manual = manualSteps;
    if (manual == null || manual == 0) return null;
    return (detectedSteps - manual) / manual * 100;
  }
}

/// 탈것 구간 하나(board~alight). 정답 걸음 수는 0이다(설계 7-2).
class VehicleInterval {
  const VehicleInterval({
    required this.boardMs,
    required this.alightMs,
    required this.kind,
    required this.detectedSteps,
  });

  final int boardMs;
  final int alightMs;

  /// board의 값(bus·subway·vehicle).
  final String kind;
  final int detectedSteps;
}

int _stepsBetween(List<int> stepTimes, int fromMs, int toMs) =>
    stepTimes.where((t) => t >= fromMs && t <= toMs).length;

/// count_start 다음의 count_end를 짝지어 구간을 만든다. count_end 전에 count_start를 또 누르면 나중 것을 쓴다.
List<CountInterval> countIntervals(List<MarkReading> marks, List<int> stepTimes) {
  final intervals = <CountInterval>[];
  int? start;
  for (final mark in marks) {
    if (mark.kind == MarkReading.countStart) {
      start = mark.tMs;
    } else if (mark.kind == MarkReading.countEnd) {
      final from = start;
      if (from == null) continue;
      intervals.add(CountInterval(
        startMs: from,
        endMs: mark.tMs,
        manualSteps: int.tryParse(mark.value.trim()),
        detectedSteps: _stepsBetween(stepTimes, from, mark.tMs),
      ));
      start = null;
    }
  }
  return intervals;
}

/// board 다음의 alight를 짝지어 구간을 만든다. 내리기 전에 세션이 끝난 탑승은 넣지 않는다(끝을 모른다).
List<VehicleInterval> vehicleIntervals(List<MarkReading> marks, List<int> stepTimes) {
  final intervals = <VehicleInterval>[];
  MarkReading? boarded;
  for (final mark in marks) {
    if (mark.kind == MarkReading.board) {
      boarded = mark;
    } else if (mark.kind == MarkReading.alight) {
      final from = boarded;
      if (from == null) continue;
      intervals.add(VehicleInterval(
        boardMs: from.tMs,
        alightMs: mark.tMs,
        kind: from.value,
        detectedSteps: _stepsBetween(stepTimes, from.tMs, mark.tMs),
      ));
      boarded = null;
    }
  }
  return intervals;
}

/// 상태별로 머문 시간(초). 첫 분류 전은 unknown이다.
Map<String, double> stateSeconds(StepRun run) {
  final seconds = <String, double>{
    'unknown': 0,
    for (final state in StepState.values) state.name: 0,
  };
  final states = run.states;
  final firstMs = states.isEmpty ? run.endMs : states.first.tMs;
  seconds['unknown'] = (firstMs - run.startMs) / 1000;
  for (var k = 0; k < states.length; k++) {
    final untilMs = k + 1 < states.length ? states[k + 1].tMs : run.endMs;
    final name = states[k].state.name;
    seconds[name] = seconds[name]! + (untilMs - states[k].tMs) / 1000;
  }
  return seconds;
}

Map<String, Object?> stepSummary(StepRun run, List<MarkReading> marks) => {
      'session_id': run.sessionId,
      'detector_id': run.detectorId,
      'detector_params': run.detectorParams,
      'start_ms': run.startMs,
      'end_ms': run.endMs,
      'duration_s': (run.endMs - run.startMs) / 1000,
      'total_steps': run.totalSteps,
      'state_seconds': stateSeconds(run),
      'count_intervals': [
        for (final c in countIntervals(marks, run.stepTimes))
          {
            'start_ms': c.startMs,
            'end_ms': c.endMs,
            'manual_steps': c.manualSteps,
            'detected_steps': c.detectedSteps,
            'error_pct': c.errorPct,
          },
      ],
      'vehicle_intervals': [
        for (final v in vehicleIntervals(marks, run.stepTimes))
          {
            'board_ms': v.boardMs,
            'alight_ms': v.alightMs,
            'kind': v.kind,
            'detected_steps': v.detectedSteps,
          },
      ],
    };

/// [outDir]에 steps.csv·step_states.csv·step_summary.json을 쓴다(폴더가 없으면 만든다).
Future<void> writeStepsOutput(StepRun run, List<MarkReading> marks, Directory outDir) async {
  await outDir.create(recursive: true);

  String csv(List<String> header, Iterable<List<Object?>> rows) {
    final buffer = StringBuffer()..writeln(header.join(','));
    for (final row in rows) {
      buffer.writeln(row.map(formatCsvField).join(','));
    }
    return buffer.toString();
  }

  await File(p.join(outDir.path, StepsSchema.stepsFile)).writeAsString(csv(
    StepsSchema.stepsHeader,
    [for (var k = 0; k < run.stepTimes.length; k++) [run.stepTimes[k], k + 1]],
  ));
  await File(p.join(outDir.path, StepsSchema.statesFile)).writeAsString(csv(
    StepsSchema.statesHeader,
    [for (final s in run.states) [s.tMs, s.state.name, s.cadenceHz]],
  ));
  await File(p.join(outDir.path, StepsSchema.summaryFile))
      .writeAsString(const JsonEncoder.withIndent('  ').convert(stepSummary(run, marks)));
}
