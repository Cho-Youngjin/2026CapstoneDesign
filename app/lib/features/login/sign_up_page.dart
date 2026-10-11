import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_exception.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../wallet/widgets/sub_page_header.dart';
import 'auth_validators.dart';
import 'widgets/auth_text_field.dart';

/// 이메일 회원가입(이메일 가입 설계 §3.2). 가입에 성공하면 로그인된 상태가 되어 라우터가 여행 탭으로 보낸다.
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nickname.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(authRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.signUpWithEmail(
        email: _email.text.trim(),
        password: _password.text,
        nickname: _nickname.text.trim(),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e.code));
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
            const SubPageHeader(title: '회원가입'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthTextField(
                        label: '닉네임',
                        controller: _nickname,
                        fieldKey: const Key('signUpNicknameField'),
                        validator: validateNickname,
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        label: '이메일',
                        controller: _email,
                        fieldKey: const Key('signUpEmailField'),
                        validator: validateEmail,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        label: '비밀번호 (6자 이상)',
                        controller: _password,
                        fieldKey: const Key('signUpPasswordField'),
                        validator: validateNewPassword,
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        label: '비밀번호 확인',
                        controller: _confirm,
                        fieldKey: const Key('signUpConfirmField'),
                        validator: (v) => validatePasswordConfirm(v, _password.text),
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
                      const SizedBox(height: 20),
                      PillButton(
                        key: const Key('signUpButton'),
                        label: _busy ? '가입 중…' : '가입하기',
                        onPressed: _busy ? null : _submit,
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
