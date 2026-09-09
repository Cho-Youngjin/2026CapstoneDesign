import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, this.onSignIn});

  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('해외여행 발걸음', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: onSignIn,
              child: const Text('Google로 계속하기'),
            ),
          ],
        ),
      ),
    );
  }
}
