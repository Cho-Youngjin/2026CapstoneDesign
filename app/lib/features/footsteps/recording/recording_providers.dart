import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../lab/recording_permissions.dart';
import 'recording_controller.dart';
import 'session_library.dart';

final recordingControllerProvider =
    Provider<RecordingController>((ref) => ForegroundRecordingController());

/// 권한 요청 함수. 위젯 테스트는 실제 권한 창 대신 정해 둔 결과를 넣는다.
final recordingPermissionRequesterProvider =
    Provider<Future<List<PermissionItem>> Function()>((ref) => requestRecordingPermissions);

final sessionLibraryProvider = Provider<SessionLibrary>((ref) => SessionLibrary(defaultSessionsRoot));

/// 세션 하나를 zip으로 묶어 Android 공유 창을 연다. zip은 앱 캐시 폴더에 만든다.
final sessionSharerProvider = Provider<Future<void> Function(SessionSummary session)>((ref) {
  final library = ref.watch(sessionLibraryProvider);
  return (session) async {
    final zip = await library.zip(session, await getTemporaryDirectory());
    await SharePlus.instance.share(
      ShareParams(files: [XFile(zip.path)], subject: '발걸음 세션 ${session.id}'),
    );
  };
});
