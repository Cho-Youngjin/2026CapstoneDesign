import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/travel_alert.dart';
import 'alert_badge.dart';

/// 주변 탭의 여행경보 영역. 경보마다 등급 배지와 그 경보의 대상 지역을 함께 보여준다 —
/// 지역을 빼면 후쿠시마 일부 지역에만 걸린 3단계가 "일본 전체 철수권고"처럼 읽힌다.
///
/// "경보 없음"은 데이터를 실제로 불러왔는데 비어 있을 때만 말한다. 국가가 아직 정해지지
/// 않았거나([alerts]가 null) 불러오는 중이면 아무것도 보여주지 않고, 불러오지 못했으면
/// 그 사실을 알린다 — 모르는 것을 "없음"(= 안전)으로 단정하지 않는다.
class AlertSection extends StatelessWidget {
  const AlertSection({super.key, required this.alerts});

  final AsyncValue<List<TravelAlert>>? alerts;

  @override
  Widget build(BuildContext context) {
    final alerts = this.alerts;
    if (alerts == null) return const SizedBox.shrink();

    return alerts.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const _AlertNote('여행경보를 불러오지 못했습니다'),
      data: (list) {
        if (list.isEmpty) return const _AlertNote('등록된 여행경보 없음');
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in list)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AlertBadge(level: a.level),
                      if (a.region.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 4),
                          child: Text(
                            a.region,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AlertNote extends StatelessWidget {
  const _AlertNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
      ),
    );
  }
}
