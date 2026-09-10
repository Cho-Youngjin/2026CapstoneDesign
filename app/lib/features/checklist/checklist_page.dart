import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/country_api.dart';

class ChecklistPage extends ConsumerWidget {
  const ChecklistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countries = ref.watch(countryListProvider);

    return countries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('국가 목록을 불러오지 못했습니다\n$e', textAlign: TextAlign.center),
        ),
      ),
      data: (list) => ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => ListTile(
          title: Text(list[i].nameKo),
          subtitle: Text(list[i].nameEn ?? '-'),
          trailing: Text('Tier ${list[i].tier}'),
        ),
      ),
    );
  }
}
