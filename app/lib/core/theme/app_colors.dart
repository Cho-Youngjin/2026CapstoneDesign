import 'package:flutter/material.dart';

/// 와이어프레임(Claude Design "해외여행 발걸음 - 와이어프레임")에서 추출한 색상 토큰.
/// 그림자 없음 · 하드라인 보더 · 낮은 채도가 이 디자인의 특징이다.
class AppColors {
  AppColors._();

  /// 주요 액션(버튼, 강조 텍스트, 진행 중 상태)에 쓰는 파란색.
  static const accent = Color(0xFF0071E3);

  /// 제목/본문 등 가장 진한 텍스트 색.
  static const ink = Color(0xFF1D1D1F);

  /// 화면 배경색.
  static const surface = Color(0xFFF5F5F7);

  /// 경고/주의(여권 재발급 필요, 여행경보 등)에 쓰는 주황색.
  static const warn = Color(0xFFB25E09);
  static const warnBg = Color(0xFFFDF3E7);
  static const warnBorder = Color(0xFFF3DEC2);

  /// 안내/정보(무비자 안내 등)에 쓰는 옅은 파란색.
  static const infoBg = Color(0xFFEAF3FE);
  static const infoBorder = Color(0xFFCFE4FB);

  /// 보더 색 — 진할수록 카드/입력창, 연할수록 리스트 구분선.
  static const borderMedium = Color(0xFFD2D2D7);
  static const borderLight = Color(0xFFE8E8ED);
  static const borderCard = Color(0xFFE0E0E6);
  static const dividerFaint = Color(0xFFF2F2F5);

  /// 보조 텍스트 색 (연할수록 덜 중요한 텍스트).
  static const textSecondary = Color(0xFF86868B);
  static const textTertiary = Color(0xFF6E6E73);
  static const textBody = Color(0xFF48484A);

  /// placeholder 막대(실제 카피가 없는 자리)에 쓰는 회색.
  static const placeholderPrimary = Color(0xFFC7C7CC);
  static const placeholderSecondary = Color(0xFFE3E3E8);

  /// 이미지/지도 placeholder의 대각선 줄무늬 두 색.
  static const stripeA = Color(0xFFEDEDF2);
  static const stripeB = Color(0xFFF7F7FA);

  /// 채팅 화면 배경(다른 화면보다 한 톤 어두운 회색).
  static const chatBg = Color(0xFFF7F7FA);
}
