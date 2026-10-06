import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/embassy.dart';

class EmbassyCard extends StatelessWidget {
  const EmbassyCard({super.key, required this.embassy});

  final Embassy embassy;

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // 공공데이터에 전화번호나 주소가 비어 있는 분관이 섞여 있다. 번호가 없으면
  // 버튼을 비활성화해 눌러도 아무 일이 없는 전화 앱 호출을 막는다.
  VoidCallback? _callAction(String? phone) =>
      (phone == null || phone.isEmpty) ? null : () => _call(phone);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${embassy.type} · ${embassy.name}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              embassy.address?.isNotEmpty == true ? embassy.address! : '주소 정보 없음',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _callAction(embassy.phone),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('대표전화'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _callAction(embassy.emergencyPhone),
                  icon: const Icon(Icons.emergency_outlined, size: 18),
                  label: const Text('긴급연락'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
