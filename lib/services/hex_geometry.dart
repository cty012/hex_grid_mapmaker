import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/enums.dart';
import 'package:hex_grid_mapmaker/models/hex_tile.dart';

/// Pure coordinate conversion functions — shared by painter and editor.

Offset hexToPixel(MapOrientation orientation, double hexSize, HexTile tile) =>
    hexFracToPixel(orientation, hexSize, tile.q.toDouble(), tile.r.toDouble());

Offset hexFracToPixel(
    MapOrientation orientation, double hexSize, double q, double r) {
  if (orientation == MapOrientation.pointyTopped) {
    return Offset(hexSize * math.sqrt(3) * (q + r / 2), hexSize * 1.5 * r);
  } else {
    return Offset(hexSize * 1.5 * q, hexSize * math.sqrt(3) * (r + q / 2));
  }
}

List<Offset> hexCorners(
    MapOrientation orientation, double hexSize, Offset center) {
  final isPointy = orientation == MapOrientation.pointyTopped;
  return List.generate(6, (i) {
    final angleRad = math.pi / 180 * (60 * i - (isPointy ? 30 : 0));
    return Offset(
      center.dx + hexSize * math.cos(angleRad),
      center.dy + hexSize * math.sin(angleRad),
    );
  });
}

HexTile pixelToHex(MapOrientation orientation, double hexSize, Offset pixel) {
  double q, r;
  if (orientation == MapOrientation.pointyTopped) {
    q = (math.sqrt(3) / 3 * pixel.dx - 1 / 3 * pixel.dy) / hexSize;
    r = (2 / 3 * pixel.dy) / hexSize;
  } else {
    q = (2 / 3 * pixel.dx) / hexSize;
    r = (-1 / 3 * pixel.dx + math.sqrt(3) / 3 * pixel.dy) / hexSize;
  }
  return _hexRound(q, r);
}

HexTile _hexRound(double fracQ, double fracR) {
  final fracS = -fracQ - fracR;
  var q = fracQ.round(), r = fracR.round();
  final s = fracS.round();
  final qDiff = (q - fracQ).abs();
  final rDiff = (r - fracR).abs();
  final sDiff = (s - fracS).abs();
  if (qDiff > rDiff && qDiff > sDiff) {
    q = -r - s;
  } else if (rDiff > sDiff) {
    r = -q - s;
  }
  return HexTile(q: q, r: r);
}
