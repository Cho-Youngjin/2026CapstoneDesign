import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';

/// 여행 탭 헤더의 계정 아이콘에서 여는 시트(이메일 가입 설계 §3.4).
Future<void> showAccountSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      builder: (_) => const AccountSheet(),
    );

/// 표시 이름·이메일과 [로그아웃]. 로그아웃하면 인증 상태가 바뀌어 라우터가 로그인 화면으로 보낸다.
/// 가입 직후에도 닉네임이 보이도록 로그인 상태 스트림이 아니라 저장소의 최신 사용자(currentUser)를 읽는다.
class AccountSheet extends ConsumerWidget {
  const AccountSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(authRepositoryProvider);
    final user = repo.currentUser;
    final email = user?.email;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user?.displayLabel ?? '로그인 정보 없음', style: AppTextStyles.cardTitle),
            if (email != null && email.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(email, style: AppTextStyles.caption),
            ],
            const SizedBox(height: 20),
            PillOutlineButton(
              key: const Key('signOutButton'),
              label: '로그아웃',
              onPressed: () async {
                Navigator.of(context).pop();
                await repo.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}
