import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lab/recording_permissions.dart';
import 'recording_controller.dart';

final recordingControllerProvider =
    Provider<RecordingController>((ref) => ForegroundRecordingController());

/// 권한 요청 함수. 위젯 테스트는 실제 권한 창 대신 정해 둔 결과를 넣는다.
final recordingPermissionRequesterProvider =
    Provider<Future<List<PermissionItem>> Function()>((ref) => requestRecordingPermissions);
