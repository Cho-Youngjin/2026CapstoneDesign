import 'package:flutter/material.dart';

Color alertColorForLevel(int level) {
  switch (level) {
    case 1:
      return Colors.blue;
    case 2:
      return Colors.yellow.shade800;
    case 3:
      return Colors.orange;
    case 4:
    default:
      return Colors.red;
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
    default:
      return '흑색경보 (여행금지)';
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
