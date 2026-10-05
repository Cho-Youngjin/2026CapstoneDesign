import 'package:flutter/material.dart';

// 서버는 원문을 파싱하지 못했거나 알 수 없는 단계일 때 level 0을 내려준다.
// 이것을 흑색경보(여행금지)로 보여주면 없는 경보를 단정하게 되므로, 단정하지 않는
// 중립 표시로 따로 다룬다 — 미검증 데이터로 잘못된 안내를 하지 않는다는 원칙.
Color alertColorForLevel(int level) {
  switch (level) {
    case 1:
      return Colors.blue;
    case 2:
      return Colors.yellow.shade800;
    case 3:
      return Colors.orange;
    case 4:
      return Colors.red;
    default:
      return Colors.grey;
  }
}

String alertLabelForLevel(int level) {
  switch (level) {
    case 1:
      return '남색경보 (여행유의)';
    case 2:
      return '황색경보 (여행자제)';
    case 3:
      return '적색경보 (철수권고)';
    case 4:
      return '흑색경보 (여행금지)';
    default:
      return '경보 확인 필요';
  }
}

class AlertBadge extends StatelessWidget {
  const AlertBadge({super.key, required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final color = alertColorForLevel(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        alertLabelForLevel(level),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
