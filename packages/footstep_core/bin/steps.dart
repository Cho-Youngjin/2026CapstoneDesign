import 'dart:io';

import 'package:footstep_core/src/cli/steps_cli.dart';

/// `dart run footstep_core:steps ...` (packages/footstep_core/에서). 사용법은 docs/research/steps-guide.md.
Future<void> main(List<String> arguments) async {
  exitCode = await runStepsCli(arguments);
}
