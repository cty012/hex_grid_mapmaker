/// Polylabel: finds the Pole of Inaccessibility of a polygon.
///
/// The Pole of Inaccessibility is the point inside a polygon that is farthest
/// from any edge — the optimal position for placing a text label because it
/// maximizes readability and minimizes overlap with boundaries.
///
/// ## Algorithm
///
/// This is a Dart port of [Mapbox's Polylabel](https://github.com/mapbox/polylabel):
///
/// 1. Compute the bounding box of the polygon.
/// 2. Divide the bounding box into a grid of square cells.
/// 3. For each cell, compute the signed distance from its center to the
///    nearest polygon edge (positive = inside, negative = outside).
/// 4. Track the best cell (maximum distance = deepest inside the polygon).
/// 5. Subdivide promising cells (those whose maximum possible distance
///    exceeds the current best) into 4 quadrants.
/// 6. Repeat until the improvement falls below [precision].
///
/// ## Performance
///
/// The [Cell] factory constructor computes `pointToPolygonDist` exactly once
/// and derives `max` from it. A previous version called it twice per cell,
/// making the algorithm 2x slower than necessary.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The result of a Polylabel computation.
class PolylabelResult {
  /// The optimal label placement point (Pole of Inaccessibility).
  final Offset center;

  /// The distance from [center] to the nearest polygon edge.
  final double distance;

  PolylabelResult(this.center, this.distance);
}

/// A candidate cell in the Polylabel subdivision grid.
///
/// Each cell represents a square region of the bounding box. The algorithm
/// evaluates cells by their signed distance [d] (how deep inside the polygon
/// the cell center is) and their theoretical maximum [max] (the farthest any
/// point in this cell could possibly be from an edge).
class Cell implements Comparable<Cell> {
  /// Cell center x-coordinate.
  final double x;

  /// Cell center y-coordinate.
  final double y;

  /// Half-size of the cell (distance from center to edge).
  final double h;

  /// Signed distance from cell center to nearest polygon edge.
  /// Positive = inside, negative = outside.
  final double d;

  /// Upper bound on distance for any point within this cell.
  /// Computed as `d + h * √2` (the cell's diagonal half-length).
  final double max;

  Cell._(this.x, this.y, this.h, this.d, this.max);

  /// Creates a Cell, computing [pointToPolygonDist] exactly once.
  factory Cell(double x, double y, double h, List<List<Offset>> polygon) {
    final d = pointToPolygonDist(x, y, polygon);
    return Cell._(x, y, h, d, d + h * math.sqrt(2));
  }

  /// Cells with higher [max] are processed first (descending priority).
  @override
  int compareTo(Cell other) => other.max.compareTo(max);
}

/// Computes the signed distance from point (x, y) to the nearest edge of
/// a multi-ring polygon.
///
/// - **Positive** → point is inside the polygon.
/// - **Negative** → point is outside the polygon.
///
/// Uses the ray-casting algorithm for inside/outside testing and projects
/// the point onto each edge segment to find the minimum distance.
double pointToPolygonDist(double x, double y, List<List<Offset>> polygon) {
  bool inside = false;
  double minDistSq = double.infinity;

  for (final ring in polygon) {
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      // Ray-casting: toggle inside flag when the ray crosses an edge.
      if ((a.dy > y) != (b.dy > y) &&
          (x < (b.dx - a.dx) * (y - a.dy) / (b.dy - a.dy) + a.dx)) {
        inside = !inside;
      }
      // Track the minimum squared distance to any edge segment.
      minDistSq = math.min(minDistSq, _segDistSq(x, y, a, b));
    }
  }
  return (inside ? 1 : -1) * math.sqrt(minDistSq);
}

/// Returns the squared distance from point (px, py) to segment a→b.
///
/// Projects the point onto the infinite line through a and b, then clamps
/// the projection parameter `t` to [0, 1] to stay within the segment.
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

/// Finds the Pole of Inaccessibility — the point inside [polygon] that is
/// farthest from any edge.
///
/// [polygon] is a list of rings: the first ring is the outer boundary,
/// subsequent rings are holes. Each ring is a list of vertices.
///
/// [precision] controls how close to optimal the result must be (in pixels).
/// Lower values give more accurate results but take longer to compute.
PolylabelResult polylabel(List<List<Offset>> polygon,
    {double precision = 1.0}) {
  if (polygon.isEmpty || polygon[0].isEmpty) {
    return PolylabelResult(Offset.zero, 0);
  }

  // Compute bounding box of the outer ring.
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

  // Seed the queue with an initial grid of cells covering the bounding box.
  for (double x = minX; x < maxX; x += cellSize) {
    for (double y = minY; y < maxY; y += cellSize) {
      cellQueue.add(Cell(x + h, y + h, h, polygon));
    }
  }

  // Start with the best cell from the initial grid.
  var bestCell = cellQueue.reduce((a, b) => a.d > b.d ? a : b);
  // Also consider the bounding box center as a candidate.
  final bboxCell = Cell(minX + width / 2, minY + height / 2, 0, polygon);
  if (bboxCell.d > bestCell.d) bestCell = bboxCell;

  // Iteratively subdivide the most promising cells.
  while (cellQueue.isNotEmpty) {
    cellQueue.sort(); // Priority: highest max first.
    final cell = cellQueue.removeAt(0);
    if (cell.d > bestCell.d) bestCell = cell;
    // Prune cells that can't possibly beat the current best.
    if (cell.max - bestCell.d <= precision) continue;

    // Subdivide into 4 quadrants.
    final halfH = cell.h / 2;
    cellQueue.add(Cell(cell.x - halfH, cell.y - halfH, halfH, polygon));
    cellQueue.add(Cell(cell.x + halfH, cell.y - halfH, halfH, polygon));
    cellQueue.add(Cell(cell.x - halfH, cell.y + halfH, halfH, polygon));
    cellQueue.add(Cell(cell.x + halfH, cell.y + halfH, halfH, polygon));
  }

  return PolylabelResult(Offset(bestCell.x, bestCell.y), bestCell.d);
}
