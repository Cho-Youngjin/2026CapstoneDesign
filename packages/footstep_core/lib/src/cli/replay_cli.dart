import 'dart:io';

import 'package:args/args.dart';

import '../detectors/detector_registry.dart';
import '../detectors/step_detector.dart';
import 'key_values.dart';
import '../policies/collection_policy.dart';
import '../policies/policy_registry.dart';
import '../replay/replay_engine.dart';
import '../replay/replay_output.dart';
import '../replay/replay_result.dart';
import '../session/session_reader.dart';

const _usage = '사용법: dart run footstep_core:replay --session <세션 폴더> --policy <정책 id> '
    '--out <결과 폴더> [--param k=v ...] [--detector os|brajdic|adaptive] '
    '[--detector-param k=v ...] [--ttff 초]';

/// 재생기 CLI(설계 5-4). 종료 코드는 sysexits 관례를 따른다: 0 성공, 64 사용법 오류,
/// 65 기록 없는 세션, 66 세션 폴더 없음. 테스트가 출력을 확인할 수 있게 [out]·[err]를 받는다.
Future<int> runReplayCli(List<String> arguments, {StringSink? out, StringSink? err}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final parser = ArgParser()
    ..addOption('session', help: 'R1 세션 폴더')
    ..addOption('policy', help: '정책 id (${policyIds.join(', ')})')
    ..addMultiOption('param', help: '정책 파라미터 k=v (여러 번 줄 수 있다)', splitCommas: false)
    ..addOption('detector', defaultsTo: 'os', help: '걸음 감지기 (${detectorIds.join(', ')})')
    ..addMultiOption('detector-param',
        help: '걸음 감지기 파라미터 k=v (여러 번 줄 수 있다)', splitCommas: false)
    ..addOption('ttff', defaultsTo: '0', help: '측위 지연(초): 0·5·10')
    ..addOption('out', help: '결과 폴더(fixes.csv, actions.csv, summary.json)');

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
  final policyId = args.option('policy');
  final outPath = args.option('out');
  if (sessionPath == null || policyId == null || outPath == null) {
    return usageError('--session, --policy, --out은 꼭 줘야 합니다.');
  }

  final ttffSeconds = double.tryParse(args.option('ttff')!);
  if (ttffSeconds == null || !ttffSeconds.isFinite || ttffSeconds < 0) return usageError('--ttff는 0 이상의 초여야 합니다.');

  final Map<String, String> params;
  final Map<String, String> detectorParams;
  try {
    params = parseKeyValues(args.multiOption('param'));
    detectorParams = parseKeyValues(args.multiOption('detector-param'));
  } on FormatException catch (e) {
    return usageError(e.message);
  }

  late final CollectionPolicy policy;
  late final StepDetector detector;
  try {
    policy = createPolicy(policyId, params);
    detector = createDetector(args.option('detector')!, detectorParams);
  } on ArgumentError catch (e) {
    return usageError('${e.message}');
  }

  final sessionDir = Directory(sessionPath);
  if (!await sessionDir.exists()) {
    stderrSink.writeln('세션 폴더가 없습니다: $sessionPath');
    return 66;
  }
  final data = await readSession(sessionDir);

  final ReplayResult result;
  try {
    result = replaySession(data, policy, detector,
        config: ReplayConfig(ttffMs: (ttffSeconds * 1000).round()));
  } on ArgumentError catch (e) {
    stderrSink.writeln('${e.message}');
    return 65;
  }

  await writeReplayOutput(result, Directory(outPath));
  final s = result.summary;
  stdoutSink.writeln('${s.policyId} fixes=${s.totalFixes} requests=${s.fixRequests} '
      'failures=${s.fixFailures} gps_on=${(s.gpsOnMs / 1000).toStringAsFixed(0)}s '
      'fixes/h=${s.fixesPerHour.toStringAsFixed(1)} skipped_rows=${data.skippedRows} -> $outPath');
  return 0;
}
