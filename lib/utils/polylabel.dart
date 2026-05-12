import 'dart:math' as math;

import 'package:flutter/material.dart';

class PolylabelResult {
  final Offset center;
  final double distance;
  PolylabelResult(this.center, this.distance);
}

class Cell implements Comparable<Cell> {
  final double x, y, h, d;
  final double max;

  Cell._(this.x, this.y, this.h, this.d, this.max);

  /// Fixed: computes pointToPolygonDist only ONCE (was called twice before).
  factory Cell(double x, double y, double h, List<List<Offset>> polygon) {
    final d = pointToPolygonDist(x, y, polygon);
    return Cell._(x, y, h, d, d + h * math.sqrt(2));
  }

  @override
  int compareTo(Cell other) => other.max.compareTo(max);
}

double pointToPolygonDist(double x, double y, List<List<Offset>> polygon) {
  bool inside = false;
  double minDistSq = double.infinity;

  for (final ring in polygon) {
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.dy > y) != (b.dy > y) &&
          (x < (b.dx - a.dx) * (y - a.dy) / (b.dy - a.dy) + a.dx)) {
        inside = !inside;
      }
      minDistSq = math.min(minDistSq, _segDistSq(x, y, a, b));
    }
  }
  return (inside ? 1 : -1) * math.sqrt(minDistSq);
}

double _segDistSq(double px, double py, Offset a, Offset b) {
  double x = a.dx, y = a.dy;
  double dx = b.dx - x, dy = b.dy - y;
  if (dx != 0 || dy != 0) {
    final t = ((px - x) * dx + (py - y) * dy) / (dx * dx + dy * dy);
    if (t > 1) {
      x = b.dx;
      y = b.dy;
    } else if (t > 0) {
      x += dx * t;
      y += dy * t;
    }
  }
  dx = px - x;
  dy = py - y;
  return dx * dx + dy * dy;
}

PolylabelResult polylabel(List<List<Offset>> polygon,
    {double precision = 1.0}) {
  if (polygon.isEmpty || polygon[0].isEmpty) {
    return PolylabelResult(Offset.zero, 0);
  }

  double minX = double.infinity, minY = double.infinity;
  double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final p in polygon[0]) {
    if (p.dx < minX) minX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy > maxY) maxY = p.dy;
  }

  final width = maxX - minX, height = maxY - minY;
  final cellSize = math.min(width, height);
  if (cellSize == 0) return PolylabelResult(polygon[0][0], 0);

  final h = cellSize / 2;
  final cellQueue = <Cell>[];

  for (double x = minX; x < maxX; x += cellSize) {
    for (double y = minY; y < maxY; y += cellSize) {
      cellQueue.add(Cell(x + h, y + h, h, polygon));
    }
  }

  var bestCell = cellQueue.reduce((a, b) => a.d > b.d ? a : b);
  final bboxCell = Cell(minX + width / 2, minY + height / 2, 0, polygon);
  if (bboxCell.d > bestCell.d) bestCell = bboxCell;

  while (cellQueue.isNotEmpty) {
    cellQueue.sort();
    final cell = cellQueue.removeAt(0);
    if (cell.d > bestCell.d) bestCell = cell;
    if (cell.max - bestCell.d <= precision) continue;

    final halfH = cell.h / 2;
    cellQueue.add(Cell(cell.x - halfH, cell.y - halfH, halfH, polygon));
    cellQueue.add(Cell(cell.x + halfH, cell.y - halfH, halfH, polygon));
    cellQueue.add(Cell(cell.x - halfH, cell.y + halfH, halfH, polygon));
    cellQueue.add(Cell(cell.x + halfH, cell.y + halfH, halfH, polygon));
  }

  return PolylabelResult(Offset(bestCell.x, bestCell.y), bestCell.d);
}
