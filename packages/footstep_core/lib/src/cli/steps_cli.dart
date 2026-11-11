import 'dart:io';

import 'package:args/args.dart';

import '../detectors/detector_registry.dart';
import '../detectors/step_detector.dart';
import '../session/session_reader.dart';
import '../steps/step_run.dart';
import '../steps/steps_output.dart';
import 'key_values.dart';

const _usage = '사용법: dart run footstep_core:steps --session <세션 폴더> '
    '--detector os|brajdic|adaptive --out <결과 폴더> [--detector-param k=v ...]';

/// 걸음 감지 CLI. 감지기 하나만 세션에 돌려 걸음 시각·상태·걸음 세기 구간을 쓴다.
/// 종료 코드는 재생기와 같다: 0 성공, 64 사용법 오류, 65 기록 없는 세션, 66 세션 폴더 없음.
Future<int> runStepsCli(List<String> arguments, {StringSink? out, StringSink? err}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final parser = ArgParser()
    ..addOption('session', help: 'R1 세션 폴더')
    ..addOption('detector', help: '걸음 감지기 (${detectorIds.join(', ')})')
    ..addMultiOption('detector-param',
        help: '걸음 감지기 파라미터 k=v (여러 번 줄 수 있다)', splitCommas: false)
    ..addOption('out', help: '결과 폴더(steps.csv, step_states.csv, step_summary.json)');

  int usageError(String message) {
    stderrSink
      ..writeln(message)
      ..writeln(_usage)
      ..writeln(parser.usage);
    return 64;
  }

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    return usageError(e.message);
  }

  final sessionPath = args.option('session');
  final detectorId = args.option('detector');
  final outPath = args.option('out');
  if (sessionPath == null || detectorId == null || outPath == null) {
    return usageError('--session, --detector, --out은 꼭 줘야 합니다.');
  }

  final StepDetector detector;
  try {
    detector = createDetector(detectorId, parseKeyValues(args.multiOption('detector-param')));
  } on FormatException catch (e) {
    return usageError(e.message);
  } on ArgumentError catch (e) {
    return usageError('${e.message}');
  }

  final sessionDir = Directory(sessionPath);
  if (!await sessionDir.exists()) {
    stderrSink.writeln('세션 폴더가 없습니다: $sessionPath');
    return 66;
  }
  final data = await readSession(sessionDir);

  final StepRun run;
  try {
    run = runDetector(data, detector);
  } on ArgumentError catch (e) {
    stderrSink.writeln('${e.message}');
    return 65;
  }

  await writeStepsOutput(run, data.marks, Directory(outPath));
  final seconds = stateSeconds(run);
  String s(String key) => seconds[key]!.toStringAsFixed(0);
  stdoutSink.writeln('${run.detectorId} steps=${run.totalSteps} walking=${s('walking')}s '
      'still=${s('still')}s other=${s('otherMotion')}s '
      'count_intervals=${countIntervals(data.marks, run.stepTimes).length} '
      'vehicle_intervals=${vehicleIntervals(data.marks, run.stepTimes).length} '
      'skipped_rows=${data.skippedRows} -> $outPath');
  return 0;
}
