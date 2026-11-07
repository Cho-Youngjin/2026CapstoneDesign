import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recording_controller.dart';

final recordingControllerProvider =
    Provider<RecordingController>((ref) => ForegroundRecordingController());
