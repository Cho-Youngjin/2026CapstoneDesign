import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/auth/auth_providers.dart';
import '../../nearby/location/location_repository.dart';
import '../models/room.dart';
import 'chat_api.dart';
import 'chat_socket.dart';

/// 실시간 위치공유(설계 §6-④, Plan D Task 9). 앱이 앞에 있는 동안만 5초마다 내 위치를 그룹에 보내고,
/// 그룹원의 위치를 받아 지도에 띄운다. 위치는 어디에도 저장하지 않는다 — 서버도 메모리로 전달만 한다.
///
/// STOMP 연결은 채팅과 같은 [chatSocketProvider]를 쓴다(토큰 갱신·재연결을 한 곳에서 하려고).
/// 공유 연결이라 멤버가 아닌 방을 구독하면 서버가 연결째 끊어 채팅까지 끊기므로, 방 정보(REST)로
/// 멤버임을 확인한 뒤에만 구독한다(ChatRoomController와 같은 규칙).

/// 송신 간격.
const locationShareInterval = Duration(seconds: 5);

/// 이 시간 넘게 소식이 없는 그룹원은 공유를 끈 것으로 본다. 송신 간격의 네 배 — 한두 번 늦는 건 봐준다.
/// 서버는 "껐다"는 신호를 따로 보내지 않으므로 이렇게 판단한다.
const locationStaleAfter = Duration(seconds: 20);

/// 송신 박자. 테스트는 직접 흘려보내는 스트림으로 바꾼다.
final locationShareTickerProvider =
    Provider<Stream<void> Function()>((ref) => () => Stream<void>.periodic(locationShareInterval));

/// 지금 내 위치. 권한이 없으면 [LocationPermissionDeniedException], 위치 서비스가 꺼져 있으면
/// [LocationServiceDisabledException]을 던진다(필요하면 권한을 묻는다).
final locationShareReaderProvider = Provider<Future<LatLng> Function()>((ref) {
  final repository = GeolocatorLocationRepository();
  return () async {
    final p = await repository.getCurrentPosition();
    return LatLng(p.latitude, p.longitude);
  };
});

/// 그룹원이 "꺼짐"인지 따질 때 쓰는 시계. 받은 시각은 이 기기 시계로 잰다 — 보낸 사람의 ts는 기기마다
/// 시계가 달라 비교에 쓰지 않는다.
final locationShareClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class MemberLocation {
  const MemberLocation({required this.position, required this.receivedAt});

  final LatLng position;
  final DateTime receivedAt;
}

class LocationShareState {
  const LocationShareState({
    this.loading = true,
    this.loadError,
    this.room,
    this.sharing = false,
    this.starting = false,
    this.me,
    this.others = const {},
    this.notice,
    required this.now,
  });

  final bool loading;
  final Object? loadError;
  final RoomDetail? room;

  /// 내 위치를 보내는 중인가. 기본은 꺼짐(설계 §6-④) — 화면에 들어올 때마다 꺼진 채로 시작한다.
  final bool sharing;

  /// 켜는 중(권한 요청·첫 위치 읽기 중).
  final bool starting;

  /// 이 기기에서 마지막으로 읽은 내 위치. 공유를 켠 뒤에만 있다.
  final LatLng? me;

  /// 다른 그룹원의 마지막 위치(uid별).
  final Map<String, MemberLocation> others;

  /// 켜지 못한 이유 같은 안내 문구.
  final String? notice;

  /// 마지막으로 시계를 읽은 시각. 틱마다 바뀌어 "꺼짐" 표시가 저절로 갱신된다.
  final DateTime now;

  bool isStale(String uid) {
    final m = others[uid];
    return m == null || now.difference(m.receivedAt) > locationStaleAfter;
  }

  LocationShareState copyWith({
    bool? loading,
    Object? loadError,
    bool clearLoadError = false,
    RoomDetail? room,
    bool? sharing,
    bool? starting,
    LatLng? me,
    Map<String, MemberLocation>? others,
    String? notice,
    bool clearNotice = false,
    DateTime? now,
  }) =>
      LocationShareState(
        loading: loading ?? this.loading,
        loadError: clearLoadError ? null : (loadError ?? this.loadError),
        room: room ?? this.room,
        sharing: sharing ?? this.sharing,
        starting: starting ?? this.starting,
        me: me ?? this.me,
        others: others ?? this.others,
        notice: clearNotice ? null : (notice ?? this.notice),
        now: now ?? this.now,
      );
}

/// 화면 하나(방 하나)의 위치공유. 화면을 떠나면(autoDispose) 구독·틱·송신이 모두 멈춘다 —
/// 공유는 이 화면을 보고 있는 동안에만 한다.
class LocationShareSession extends Notifier<LocationShareState> {
  LocationShareSession(this.roomId);

  final int roomId;

  StreamSubscription<Map<String, dynamic>>? _locationSub;
  StreamSubscription<void>? _tickSub;
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;

  /// 진행 중인 GPS 읽기. 끝나면 null.
  Future<void>? _inFlight;

  DateTime _now() => ref.read(locationShareClockProvider)();

  @override
  LocationShareState build() {
    ref.onDispose(() {
      _locationSub?.cancel();
      _tickSub?.cancel();
      _lifecycle?.dispose();
    });
    // build 안에서는 state를 바꿀 수 없으므로 첫 조회는 다음 이벤트 루프에서 시작한다.
    Future.microtask(_load);
    return LocationShareState(now: _now());
  }

  Future<void> _load() async {
    try {
      final room = await ref.read(chatApiProvider).roomDetail(roomId);
      if (!ref.mounted) return;
      // 위치공유는 그룹 방 기능이다(Plan D Task 9). 서버 중계는 멤버 여부만 보므로 DM은 여기서 막는다.
      if (room.type != RoomType.group) {
        state = state.copyWith(loading: false, loadError: const LocationShareGroupOnly());
        return;
      }
      state = state.copyWith(loading: false, clearLoadError: true, room: room);
      _startRealtime();
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  Future<void> retry() async {
    state = state.copyWith(loading: true, clearLoadError: true);
    await _load();
  }

  void _startRealtime() {
    if (_locationSub != null) return; // 재시도로 다시 불린 경우
    final socket = ref.read(chatSocketProvider);
    _locationSub = socket.subscribe('/topic/group/$roomId/location').listen(_onBroadcast);
    _tickSub = ref.read(locationShareTickerProvider)().listen((_) => _onTick());
    // 앞에 있을 때만 보낸다. 알림창을 내리는 정도(inactive)는 앞에 있는 것으로 본다.
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) =>
          _foreground = s == AppLifecycleState.resumed || s == AppLifecycleState.inactive,
    );
  }

  void _onBroadcast(Map<String, dynamic> json) {
    final uid = json['uid'];
    final lat = json['lat'];
    final lng = json['lng'];
    if (uid is! String || lat is! num || lng is! num) return;
    // 서버는 보낸 사람에게도 되돌려 보낸다. 내 마커는 이 기기의 GPS로 그리므로 무시한다.
    if (uid == ref.read(currentUidProvider)) return;
    final now = _now();
    state = state.copyWith(
      now: now,
      others: {
        ...state.others,
        uid: MemberLocation(position: LatLng(lat.toDouble(), lng.toDouble()), receivedAt: now),
      },
    );
  }

  void _onTick() {
    state = state.copyWith(now: _now());
    if (state.sharing && _foreground) unawaited(_readAndSend());
  }

  /// 공유를 켜거나 끈다. 켤 때는 바로 한 번 보낸다(5초를 기다리지 않게). 권한이 없거나 위치 서비스가
  /// 꺼져 있으면 켜지 않고 [LocationShareState.notice]로 알린다.
  Future<void> setSharing(bool on) async {
    if (!on) {
      state = state.copyWith(sharing: false, clearNotice: true);
      return;
    }
    if (state.sharing || state.starting || state.room == null) return;
    state = state.copyWith(starting: true, clearNotice: true);
    final ok = await _readAndSend(starting: true);
    if (!ref.mounted) return;
    state = state.copyWith(starting: false, sharing: ok);
  }

  /// 위치를 읽어 보낸다. 앞선 읽기가 끝나지 않았으면(GPS가 늦게 잡힘) 틱은 건너뛴다 — 읽기가 겹쳐 쌓이지
  /// 않게. 켜기는 건너뛰면 요청이 사라지므로(끈 사이 끝난 앞선 읽기는 결과를 버린다) 끝나길 기다렸다 새로 읽는다.
  Future<bool> _readAndSend({bool starting = false}) async {
    while (_inFlight != null) {
      if (!starting) return false;
      await _inFlight;
      if (!ref.mounted) return false;
    }
    final done = Completer<void>();
    _inFlight = done.future;
    try {
      final position = await ref.read(locationShareReaderProvider)();
      if (!ref.mounted) return false;
      // 읽는 사이에 껐거나 앱이 뒤로 갔으면 보내지 않는다(앞에 있을 때만 보낸다는 약속을 지킨다).
      // 권한 대화상자는 앱을 inactive로만 만들어 앞에 있는 것으로 보므로, 켤 때도 같은 검사를 해도 된다.
      if ((!starting && !state.sharing) || !_foreground) return false;
      ref.read(chatSocketProvider).send('/app/location', {
        'roomId': '$roomId',
        'lat': position.latitude,
        'lng': position.longitude,
        'ts': _now().millisecondsSinceEpoch,
      });
      state = state.copyWith(me: position);
      return true;
    } on LocationPermissionDeniedException {
      if (ref.mounted) {
        state = state.copyWith(sharing: false, notice: '위치 권한을 허용해야 내 위치를 공유할 수 있어요.');
      }
      return false;
    } on LocationServiceDisabledException {
      if (ref.mounted) state = state.copyWith(sharing: false, notice: '기기의 위치 서비스를 켜 주세요.');
      return false;
    } catch (e) {
      // GPS가 잠깐 안 잡히는 건(타임아웃 등) 다음 틱에 다시 해 본다. 켤 때 실패하면 알린다.
      debugPrint('위치공유 위치 읽기 실패: $e');
      if (starting && ref.mounted) {
        state = state.copyWith(notice: '지금 위치를 찾지 못했어요. 잠시 후 다시 켜 주세요.');
      }
      return false;
    } finally {
      _inFlight = null;
      done.complete();
    }
  }
}

/// 그룹 방이 아니라서(DM) 위치공유를 열지 않는다.
class LocationShareGroupOnly implements Exception {
  const LocationShareGroupOnly();
}

final locationShareSessionProvider =
    NotifierProvider.autoDispose.family<LocationShareSession, LocationShareState, int>(
        LocationShareSession.new);
