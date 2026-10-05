import 'package:flutter/material.dart';

import '../models/place.dart';

class PlaceListTile extends StatelessWidget {
  const PlaceListTile({super.key, required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.place_outlined),
      title: Text(place.name),
      subtitle: Text(place.address),
      trailing: Text(place.category.label),
    );
  }
}
