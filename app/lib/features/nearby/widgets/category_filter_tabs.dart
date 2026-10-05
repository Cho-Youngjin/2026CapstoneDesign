import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/place.dart';
import '../providers/nearby_selection_providers.dart';

class CategoryFilterTabs extends ConsumerWidget {
  const CategoryFilterTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(nearbyCategoryProvider);

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: PlaceCategory.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final category = PlaceCategory.values[i];
          return ChoiceChip(
            label: Text(category.label),
            selected: category == selected,
            onSelected: (_) =>
                ref.read(nearbyCategoryProvider.notifier).state = category,
          );
        },
      ),
    );
  }
}
