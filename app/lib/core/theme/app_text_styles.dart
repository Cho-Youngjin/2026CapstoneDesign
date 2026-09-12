import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 와이어프레임의 타이포 굵기 위계: 700(제목) / 500(라벨·버튼) / 400(본문·보조).
class AppTextStyles {
  AppTextStyles._();

  static const _family = 'Noto Sans KR';

  static const screenTitle = TextStyle(
    fontFamily: _family,
    fontWeight: FontWeight.w700,
    fontSize: 18,
    color: AppColors.ink,
  );

  static const cardTitle = TextStyle(
    fontFamily: _family,
    fontWeight: FontWeight.w700,
    fontSize: 15,
    color: AppColors.ink,
  );

  static const body = TextStyle(
    fontFamily: _family,
    fontWeight: FontWeight.w500,
    fontSize: 15,
    color: AppColors.ink,
  );

  static const label = TextStyle(
    fontFamily: _family,
    fontWeight: FontWeight.w500,
    fontSize: 11,
    color: AppColors.textSecondary,
  );

  static const caption = TextStyle(
    fontFamily: _family,
    fontWeight: FontWeight.w400,
    fontSize: 11,
    color: AppColors.textTertiary,
  );

  static const buttonLarge = TextStyle(
    fontFamily: _family,
    fontWeight: FontWeight.w600,
    fontSize: 16,
    color: Colors.white,
  );

  static const chip = TextStyle(
    fontFamily: _family,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    color: AppColors.textBody,
  );
}
