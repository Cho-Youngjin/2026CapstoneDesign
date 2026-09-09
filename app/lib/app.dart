import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TravelFootstepsApp extends StatelessWidget {
  const TravelFootstepsApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '해외여행 발걸음',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
