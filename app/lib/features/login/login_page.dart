import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_exception.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/auth/firebase_auth_repository.dart' show AuthCancelledException;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../../router.dart';
import 'auth_validators.dart';
import 'widgets/auth_text_field.dart';

/// 로그인 화면 — 이메일/비밀번호와 Google 로그인(이메일 가입 설계 §3.1).
/// 로그인에 성공하면 인증 상태가 바뀌어 라우터가 여행 탭으로 보낸다 — 이 화면이 직접 이동하지 않는다.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 로그인 요청을 보내고 실패를 문구로 바꾼다. 사용자가 Google 로그인을 취소하면 아무것도 보여주지 않는다.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthCancelledException {
      // 사용자가 닫은 것이라 알릴 게 없다.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = authErrorMessage(AuthErrorCode.unknown));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _signInWithEmail() {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(authRepositoryProvider);
    _run(() => repo.signInWithEmail(email: _email.text.trim(), password: _password.text));
  }

  void _signInWithGoogle() {
    final repo = ref.read(authRepositoryProvider);
    _run(() => repo.signInWithGoogle());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '해외여행 발걸음',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 32),
                AuthTextField(
                  label: '이메일',
                  controller: _email,
                  fieldKey: const Key('loginEmailField'),
                  validator: validateEmail,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                AuthTextField(
                  label: '비밀번호',
                  controller: _password,
                  fieldKey: const Key('loginPasswordField'),
                  validator: validateLoginPassword,
                  obscureText: true,
                ),
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
                const SizedBox(height: 16),
                PillButton(
                  key: const Key('emailLoginButton'),
                  label: _busy ? '로그인 중…' : '로그인',
                  onPressed: _busy ? null : _signInWithEmail,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('forgotPasswordLink'),
                    onPressed: () => context.push(AppRoutes.passwordReset),
                    child: const Text('비밀번호를 잊으셨나요?'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.borderLight)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('또는', style: AppTextStyles.caption),
                    ),
                    const Expanded(child: Divider(color: AppColors.borderLight)),
                  ],
                ),
                const SizedBox(height: 16),
                PillOutlineButton(
                  key: const Key('googleLoginButton'),
                  label: 'Google로 계속하기',
                  onPressed: _busy ? null : _signInWithGoogle,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('계정이 없으신가요?', style: AppTextStyles.caption),
                    TextButton(
                      key: const Key('signUpLink'),
                      onPressed: () => context.push(AppRoutes.signUp),
                      child: const Text('회원가입'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
