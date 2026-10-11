import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_exception.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../wallet/widgets/sub_page_header.dart';
import 'auth_validators.dart';
import 'widgets/auth_text_field.dart';

/// 비밀번호 재설정 메일 보내기(이메일 가입 설계 §3.3). 가입 여부를 드러내지 않도록,
/// 서버가 "없는 계정"이라고 해도 보냈다는 안내를 똑같이 보여준다.
class PasswordResetPage extends ConsumerStatefulWidget {
  const PasswordResetPage({super.key});

  @override
  ConsumerState<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends ConsumerState<PasswordResetPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(authRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
      _sent = false;
    });
    try {
      await repo.sendPasswordReset(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == AuthErrorCode.invalidCredential) {
          _sent = true;
        } else {
          _error = authErrorMessage(e.code);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = authErrorMessage(AuthErrorCode.unknown));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SubPageHeader(title: '비밀번호 재설정'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('가입한 이메일로 비밀번호 재설정 링크를 보내 드립니다.', style: AppTextStyles.body),
                      const SizedBox(height: 16),
                      AuthTextField(
                        label: '이메일',
                        controller: _email,
                        fieldKey: const Key('resetEmailField'),
                        validator: validateEmail,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      if (_sent) ...[
                        const SizedBox(height: 12),
                        Text(
                          '재설정 메일을 보냈습니다. 메일함을 확인해 주세요.',
                          key: const Key('resetSentMessage'),
                          style: AppTextStyles.caption.copyWith(color: AppColors.accent),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          key: const Key('authError'),
                          style: AppTextStyles.caption.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      PillButton(
                        key: const Key('sendResetButton'),
                        label: _busy ? '보내는 중…' : '재설정 메일 보내기',
                        onPressed: _busy ? null : _send,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
