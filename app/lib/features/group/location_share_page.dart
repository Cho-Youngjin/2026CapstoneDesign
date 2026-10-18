import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../footsteps/map/base_google_map.dart';
import 'data/chat_api.dart';
import 'data/location_share_session.dart';
import 'models/room.dart';

/// 그룹 실시간 위치공유(`/group/location/:roomId`, 채팅방 상단 위치 아이콘에서 들어온다).
/// 와이어프레임: "해외여행 발걸음 - 와이어프레임" Plan D, 위치 공유 화면.
///
/// 공유는 꺼진 채로 시작하고, 켜면 이 화면을 보고 있는 동안 5초마다 내 위치를 보낸다. 화면을 떠나거나
/// 앱이 뒤로 가면 보내지 않는다. 위치는 저장하지 않는다.
class LocationSharePage extends ConsumerStatefulWidget {
  const LocationSharePage({super.key, required this.roomId});

  final int roomId;

  @override
  ConsumerState<LocationSharePage> createState() => _LocationSharePageState();
}

class _LocationSharePageState extends ConsumerState<LocationSharePage> {
  /// 처음 열 때의 지도(서울). 누구든 첫 위치가 잡히면 그쪽으로 옮긴다.
  static const _initialCamera = CameraPosition(target: LatLng(37.5665, 126.9780), zoom: 11);

  GoogleMapController? _map;
  bool _centered = false;

  void _moveTo(LatLng target) => _map?.animateCamera(CameraUpdate.newLatLngZoom(target, 15));

  /// 위치가 잡힌 사람을 모두 화면에 담는다.
  void _showAll(List<LatLng> points) {
    if (points.isEmpty) return;
    if (points.length == 1) return _moveTo(points.single);
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    _map?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
        northeast: LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
      ),
      60,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = locationShareSessionProvider(widget.roomId);
    final s = ref.watch(provider);
    final myUid = ref.watch(currentUidProvider);

    // 처음 위치가 잡히면(내 것이든 그룹원 것이든) 한 번만 그쪽으로 옮긴다. 그 뒤로는 사용자가 움직인 지도를 그대로 둔다.
    ref.listen(provider, (_, next) {
      if (_centered) return;
      final first = next.me ?? next.others.values.firstOrNull?.position;
      if (first == null || _map == null) return;
      _centered = true;
      _moveTo(first);
    });

    final Widget body;
    if (s.loadError is RoomNotFoundException) {
      body = const _Notice(message: '이 그룹을 찾을 수 없어요.\n그룹원만 위치를 볼 수 있습니다.');
    } else if (s.loadError != null) {
      body = _Notice(
        message: '그룹 정보를 불러오지 못했어요.',
        actionLabel: '다시 시도',
        onAction: () => ref.read(provider.notifier).retry(),
      );
    } else if (s.loading || s.room == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = _content(s, s.room!, myUid);
    }

    return Column(children: [const _Header(), Expanded(child: body)]);
  }

  Widget _content(LocationShareState s, RoomDetail room, String? myUid) {
    final notifier = ref.read(locationShareSessionProvider(widget.roomId).notifier);
    final names = {for (final m in room.members) m.uid: m.displayName ?? '그룹원'};
    final others = [for (final m in room.members) if (m.uid != myUid) m];
    // 방 정보를 받은 뒤에 들어온 사람도 위치가 오면 보여준다(이름은 아직 모른다).
    final strangers = [
      for (final uid in s.others.keys)
        if (!names.containsKey(uid)) RoomMember(uid: uid),
    ];

    final markers = <Marker>{
      if (s.me != null)
        Marker(
          markerId: const MarkerId('me'),
          position: s.me!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: '나'),
          zIndexInt: 1,
        ),
      for (final e in s.others.entries)
        Marker(
          markerId: MarkerId(e.key),
          position: e.value.position,
          // 소식이 끊긴 사람은 흐리게, 이름 옆에 "꺼짐"을 붙인다(마지막 위치는 남겨 둔다).
          alpha: s.isStale(e.key) ? 0.4 : 1,
          infoWindow: InfoWindow(
            title: s.isStale(e.key) ? '${names[e.key] ?? '그룹원'} · 꺼짐' : names[e.key] ?? '그룹원',
          ),
        ),
    };

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: BaseGoogleMap(
                  key: const Key('locationShareMap'),
                  initialCamera: _initialCamera,
                  markers: markers,
                  // 내 위치는 공유할 때 보내는 좌표로 마커를 그린다. 기본 파란 점까지 켜면 같은 위치가 두 번 보인다.
                  myLocationEnabled: false,
                  onMapCreated: (c) => _map = c,
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                top: 14,
                child: _ShareToggleCard(
                  sharing: s.sharing,
                  busy: s.starting,
                  notice: s.notice,
                  onTap: s.starting ? null : () => notifier.setSharing(!s.sharing),
                ),
              ),
            ],
          ),
        ),
        _MemberSheet(
          memberCount: room.members.length,
          onShowAll: () => _showAll([
            if (s.me != null) s.me!,
            for (final m in s.others.values) m.position,
          ]),
          children: [
            _MemberChip(
              key: const Key('memberChip-me'),
              name: '나',
              isMe: true,
              live: s.sharing,
              onTap: s.me == null ? null : () => _moveTo(s.me!),
            ),
            for (final m in [...others, ...strangers])
              _MemberChip(
                key: Key('memberChip-${m.uid}'),
                name: m.displayName ?? '그룹원',
                isMe: false,
                live: !s.isStale(m.uid),
                onTap: s.others[m.uid] == null ? null : () => _moveTo(s.others[m.uid]!.position),
              ),
          ],
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
      ),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.arrow_back, color: AppColors.textBody),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 12),
          Text('위치 공유', style: AppTextStyles.screenTitle),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShareToggleCard extends StatelessWidget {
  const _ShareToggleCard({
    required this.sharing,
    required this.busy,
    required this.notice,
    required this.onTap,
  });

  final bool sharing;
  final bool busy;
  final String? notice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = notice ??
        (sharing ? '5초마다 갱신 · 기록은 저장되지 않음' : '켜면 그룹원에게 5초마다 내 위치가 보여요 · 저장되지 않음');
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.borderCard),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        key: const Key('locationShareToggle'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sharing ? '내 위치 공유 ON' : '내 위치 공유 OFF',
                      style: const TextStyle(
                        fontFamily: 'Noto Sans KR',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      key: const Key('locationShareSubtitle'),
                      style: TextStyle(
                        fontFamily: 'Noto Sans KR',
                        fontWeight: FontWeight.w400,
                        fontSize: 10.5,
                        color: notice != null
                            ? Theme.of(context).colorScheme.error
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              busy
                  ? const SizedBox(
                      width: 46,
                      height: 27,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : _TogglePill(on: sharing),
            ],
          ),
        ),
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  const _TogglePill({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 46,
      height: 27,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: on ? AppColors.accent : AppColors.placeholderSecondary,
        borderRadius: BorderRadius.circular(980),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 150),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: const SizedBox(
          width: 21,
          height: 21,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class _MemberSheet extends StatelessWidget {
  const _MemberSheet({required this.memberCount, required this.onShowAll, required this.children});

  final int memberCount;
  final VoidCallback onShowAll;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.placeholderSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('그룹원 $memberCount', style: AppTextStyles.cardTitle),
              GestureDetector(
                key: const Key('showAllMembers'),
                onTap: onShowAll,
                child: Text(
                  '전체 보기',
                  style: AppTextStyles.caption.copyWith(color: AppColors.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 92, // 칩(원 48 + 이름 + 상태) 높이. 글자 크기 설정이 커져도 잘리지 않게 여유를 둔다.
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: children.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) => children[i],
            ),
          ),
        ],
      ),
    );
  }
}

/// 하단 시트의 그룹원 한 명. 공유 중이면 테두리를 강조하고, 누르면 지도를 그 사람에게 옮긴다.
class _MemberChip extends StatelessWidget {
  const _MemberChip({
    super.key,
    required this.name,
    required this.isMe,
    required this.live,
    required this.onTap,
  });

  final String name;
  final bool isMe;
  final bool live;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: live ? AppColors.accent : AppColors.borderCard,
                  width: live ? 2 : 1,
                ),
              ),
              child: Text(
                name.isEmpty ? '?' : name.characters.first,
                style: AppTextStyles.body.copyWith(
                  color: live ? AppColors.ink : AppColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Noto Sans KR',
                fontWeight: isMe ? FontWeight.w500 : FontWeight.w400,
                fontSize: 10,
                color: AppColors.ink,
              ),
            ),
            Text(
              live ? '공유 중' : '꺼짐',
              style: TextStyle(
                fontFamily: 'Noto Sans KR',
                fontSize: 9,
                color: live ? AppColors.accent : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
