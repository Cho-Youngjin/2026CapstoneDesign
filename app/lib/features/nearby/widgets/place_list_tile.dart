import 'package:flutter/material.dart';

import '../models/place.dart';

/// 현재 위치에서의 거리를 짧게 표시한다. 1km 미만은 가까운 10m 단위, 그 이상은 소수 한 자리 km다.
String formatDistance(double meters) {
  if (meters < 10) return '10m 이내';
  if (meters < 1000) {
    final rounded = (meters / 10).round() * 10;
    // 반올림하면 1000m가 되는 경우(995m 이상)는 km 표기가 자연스럽다.
    return rounded >= 1000 ? '1.0km' : '${rounded}m';
  }
  return '${(meters / 1000).toStringAsFixed(1)}km';
}

class PlaceListTile extends StatelessWidget {
  const PlaceListTile({super.key, required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final distance = place.distanceMeters;
    return ListTile(
      leading: Icon(Icons.place, color: place.category.color),
      title: Text(place.name),
      subtitle: Text(place.address),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            place.category.label,
            style: TextStyle(color: place.category.color, fontWeight: FontWeight.w600),
          ),
          if (distance != null) Text(formatDistance(distance)),
        ],
      ),
    );
  }
}
