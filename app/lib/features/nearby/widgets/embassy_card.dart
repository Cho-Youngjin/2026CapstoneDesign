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
            Text(embassy.address),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _call(embassy.phone),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('대표전화'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _call(embassy.emergencyPhone),
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
