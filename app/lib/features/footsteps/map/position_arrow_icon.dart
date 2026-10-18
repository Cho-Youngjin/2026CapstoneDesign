import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// 파란 점 + 위쪽(북쪽)을 가리키는 화살표 아이콘. Marker.rotation으로 돌려 쓴다.
Future<BitmapDescriptor> buildPositionArrowIcon() async {
  const size = 96.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const center = Offset(size / 2, size / 2);

  final arrow = Path()
    ..moveTo(size / 2, 4)
    ..lineTo(size / 2 + 16, 32)
    ..lineTo(size / 2 - 16, 32)
    ..close();
  canvas.drawPath(arrow, Paint()..color = const Color(0xFF2563EB));
  canvas.drawCircle(center, 22, Paint()..color = Colors.white);
  canvas.drawCircle(center, 17, Paint()..color = const Color(0xFF2563EB));

  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: 36, height: 36);
}
