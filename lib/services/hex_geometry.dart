/// Pure coordinate conversion between hex grid and pixel space.
///
/// These functions are shared by both [HexPainter] (for rendering) and
/// [EditorScreen] (for mouse-to-hex hit testing). Extracting them here
/// eliminates the code duplication that previously existed between the two.
///
/// ## Coordinate Systems
///
/// - **Axial (q, r)**: The discrete hex grid. See [HexTile].
/// - **Pixel (x, y)**: Continuous screen coordinates relative to the canvas center.
///
/// ## Orientation
///
/// All functions take a [MapOrientation] parameter because the mapping
/// between axial and pixel coordinates differs between pointy-topped and
/// flat-topped layouts:
///
/// - **Pointy-topped**: `x = size * √3 * (q + r/2)`, `y = size * 3/2 * r`
/// - **Flat-topped**: `x = size * 3/2 * q`, `y = size * √3 * (r + q/2)`
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/enums.dart';
import 'package:hex_grid_mapmaker/models/hex_tile.dart';

/// Converts an integer hex coordinate to pixel-space center point.
Offset hexToPixel(MapOrientation orientation, double hexSize, HexTile tile) =>
    hexFracToPixel(orientation, hexSize, tile.q.toDouble(), tile.r.toDouble());

/// Converts fractional hex coordinates to pixel-space.
///
/// Used for computing the geometric center of a set of tiles (e.g. for
/// label placement fallback when Polylabel produces tied candidates).
Offset hexFracToPixel(
    MapOrientation orientation, double hexSize, double q, double r) {
  if (orientation == MapOrientation.pointyTopped) {
    return Offset(hexSize * math.sqrt(3) * (q + r / 2), hexSize * 1.5 * r);
  } else {
    return Offset(hexSize * 1.5 * q, hexSize * math.sqrt(3) * (r + q / 2));
  }
}

/// Returns the 6 corner vertices of a hex tile centered at [center].
///
/// Corners are returned in clockwise order starting from the rightmost
/// vertex (flat-topped) or top-right vertex (pointy-topped). The starting
/// angle offset is -30° for pointy-topped and 0° for flat-topped.
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

/// Converts a pixel-space point to the nearest hex tile coordinate.
///
/// Uses the standard axial-to-cube-round algorithm:
/// 1. Compute fractional axial coordinates from pixel position.
/// 2. Round to the nearest integer cube coordinates.
/// 3. Snap the component with the largest rounding error to maintain
///    the cube constraint `q + r + s = 0`.
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

/// Rounds fractional axial coordinates to the nearest valid hex tile.
///
/// Converts to cube coordinates, rounds each axis independently, then
/// resets the axis with the largest rounding error to satisfy q + r + s = 0.
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
