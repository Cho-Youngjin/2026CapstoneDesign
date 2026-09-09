import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/checklist/checklist_page.dart';
import 'features/footsteps/footsteps_page.dart';
import 'features/group/group_page.dart';
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
          GoRoute(path: AppRoutes.group, builder: (_, _) => const GroupPage()),
          GoRoute(path: AppRoutes.translate, builder: (_, _) => const TranslatePage()),
          GoRoute(path: AppRoutes.nearby, builder: (_, _) => const NearbyPage()),
        ],
      ),
    ],
  );
}

class _TabScaffold extends StatelessWidget {
  const _TabScaffold({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final index = AppRoutes.tabs.indexOf(location);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppRoutes.tabLabels[index < 0 ? 0 : index]),
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) => context.go(AppRoutes.tabs[i]),
        destinations: [
          for (var i = 0; i < AppRoutes.tabs.length; i++)
            NavigationDestination(
              icon: Icon(AppRoutes.tabIcons[i]),
              label: AppRoutes.tabLabels[i],
            ),
        ],
      ),
    );
  }
}
