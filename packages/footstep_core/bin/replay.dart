import 'dart:io';

import 'package:footstep_core/src/cli/replay_cli.dart';

/// `dart run footstep_core:replay ...` (packages/footstep_core/에서). 사용법은 docs/research/replay-guide.md.
Future<void> main(List<String> arguments) async {
  exitCode = await runReplayCli(arguments);
}
