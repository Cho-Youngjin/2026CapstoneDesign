import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_colors.dart';
import 'features/checklist/checklist_page.dart';
import 'features/footsteps/footsteps_detail_page.dart';
import 'features/footsteps/footsteps_page.dart';
import 'features/group/chat_room_page.dart';
import 'features/group/group_page.dart';
import 'features/group/location_share_page.dart';
import 'features/login/login_page.dart';
import 'features/nearby/nearby_page.dart';
import 'features/translate/translate_page.dart';
import 'features/visa/visa_page.dart';

class AppRoutes {
  static const login = '/login';
  static const visa = '/visa';
  static const checklist = '/checklist';
  static const footsteps = '/footsteps';
  static const group = '/group';
  static const translate = '/translate';
  static const nearby = '/nearby';

  static const tabs = [visa, checklist, footsteps, group, translate, nearby];

  static const tabLabels = ['비자', '준비물', '발걸음', '그룹', '번역', '주변'];

  static const tabIcons = [
    Icons.assignment_outlined,
    Icons.checklist_outlined,
    Icons.map_outlined,
    Icons.group_outlined,
    Icons.translate_outlined,
    Icons.explore_outlined,
  ];

  /// 탭 하위 상세 화면(뒤로가기 헤더는 있지만 하단 탭바는 유지되는 화면).
  /// 실제 국가/그룹 id 라우팅은 각 Plan(C/D)에서 실 데이터 연동 시 교체한다 —
  /// 지금은 와이어프레임 UI만 보여주는 단계라 경로를 고정값으로 둔다.
  static const footstepsDetail = '/footsteps/detail';
  static const groupChat = '/group/chat';
  static const groupLocation = '/group/location';
}

GoRouter createRouter({required bool isLoggedIn, VoidCallback? onSignIn}) {
  return GoRouter(
    initialLocation: isLoggedIn ? AppRoutes.visa : AppRoutes.login,
    redirect: (context, state) {
      final goingToLogin = state.matchedLocation == AppRoutes.login;
      if (!isLoggedIn && !goingToLogin) return AppRoutes.login;
      if (isLoggedIn && goingToLogin) return AppRoutes.visa;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => LoginPage(onSignIn: onSignIn),
      ),
      ShellRoute(
        builder: (context, state, child) => _TabScaffold(
          location: state.matchedLocation,
          child: child,
        ),
        routes: [
          GoRoute(path: AppRoutes.visa, builder: (_, _) => const VisaPage()),
          GoRoute(path: AppRoutes.checklist, builder: (_, _) => const ChecklistPage()),
          GoRoute(path: AppRoutes.footsteps, builder: (_, _) => const FootstepsPage()),
          GoRoute(
            path: AppRoutes.footstepsDetail,
            builder: (_, _) => const FootstepsDetailPage(),
          ),
          GoRoute(path: AppRoutes.group, builder: (_, _) => const GroupPage()),
          GoRoute(path: AppRoutes.groupChat, builder: (_, _) => const ChatRoomPage()),
          GoRoute(
            path: AppRoutes.groupLocation,
            builder: (_, _) => const LocationSharePage(),
          ),
          GoRoute(path: AppRoutes.translate, builder: (_, _) => const TranslatePage()),
          GoRoute(path: AppRoutes.nearby, builder: (_, _) => const NearbyPage()),
        ],
      ),
    ],
  );
}

/// 탭 구조를 담당하는 셸. 상단 헤더는 화면마다 다르게 생겨서(뒤로가기, 배지,
/// 우측 액션 링크 등) 공통 AppBar를 쓰지 않고 각 페이지가 직접 헤더를 그린다 —
/// 여기서는 배경색과 하단 탭바만 책임진다.
class _TabScaffold extends StatelessWidget {
  const _TabScaffold({required this.location, required this.child});

  final String location;
  final Widget child;

  int get _activeTabIndex {
    for (var i = 0; i < AppRoutes.tabs.length; i++) {
      if (location.startsWith(AppRoutes.tabs[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: child),
      bottomNavigationBar: _WireframeTabBar(
        activeIndex: _activeTabIndex,
        onTap: (i) => context.go(AppRoutes.tabs[i]),
      ),
    );
  }
}

/// 와이어프레임의 TabBar.dc.html 컴포넌트를 그대로 옮긴 하단 탭바 —
/// 그림자 없음, 활성 탭만 파란색, 나머지는 회색.
class _WireframeTabBar extends StatelessWidget {
  const _WireframeTabBar({required this.activeIndex, required this.onTap});

  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('wireframeTabBar'),
      height: 62,
      padding: const EdgeInsets.only(bottom: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < AppRoutes.tabs.length; i++)
            Expanded(
              child: _WireframeTabItem(
                icon: AppRoutes.tabIcons[i],
                label: AppRoutes.tabLabels[i],
                active: i == activeIndex,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _WireframeTabItem extends StatelessWidget {
  const _WireframeTabItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.placeholderPrimary;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Noto Sans KR',
              fontWeight: FontWeight.w500,
              fontSize: 9.5,
              color: active ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
