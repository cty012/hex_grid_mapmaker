import 'dart:math' as math;
import 'package:flutter/material.dart';

class PolylabelResult {
  final Offset center;
  final double distance;

  PolylabelResult(this.center, this.distance);
}

class Cell implements Comparable<Cell> {
  final double x;
  final double y;
  final double h;
  final double d;
  final double max;

  Cell(this.x, this.y, this.h, List<List<Offset>> polygon)
    : d = pointToPolygonDist(x, y, polygon),
      max = pointToPolygonDist(x, y, polygon) + h * math.sqrt(2);

  @override
  int compareTo(Cell other) {
    return other.max.compareTo(max); // Descending order
  }
}

double pointToPolygonDist(double x, double y, List<List<Offset>> polygon) {
  bool inside = false;
  double minDistSq = double.infinity;

  for (int k = 0; k < polygon.length; k++) {
    final ring = polygon[k];

    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];

      if ((a.dy > y) != (b.dy > y) &&
          (x < (b.dx - a.dx) * (y - a.dy) / (b.dy - a.dy) + a.dx)) {
        inside = !inside;
      }

      minDistSq = math.min(minDistSq, getSegDistSq(x, y, a, b));
    }
  }

  return (inside ? 1 : -1) * math.sqrt(minDistSq);
}

double getSegDistSq(double px, double py, Offset a, Offset b) {
  double x = a.dx;
  double y = a.dy;
  double dx = b.dx - x;
  double dy = b.dy - y;

  if (dx != 0 || dy != 0) {
    double t = ((px - x) * dx + (py - y) * dy) / (dx * dx + dy * dy);

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

PolylabelResult polylabel(List<List<Offset>> polygon, {double precision = 1.0}) {
  if (polygon.isEmpty || polygon[0].isEmpty) return PolylabelResult(Offset.zero, 0);

  // Find bounding box
  double minX = double.infinity, minY = double.infinity;
  double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final p in polygon[0]) {
    if (p.dx < minX) minX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy > maxY) maxY = p.dy;
  }

  double width = maxX - minX;
  double height = maxY - minY;
  double cellSize = math.min(width, height);
  if (cellSize == 0) return PolylabelResult(polygon[0][0], 0);

  double h = cellSize / 2;

  // Use a simple list and sort it for a priority queue (dart lacks native PriorityQueue in core,
  // but for Polylabel the queue size rarely exceeds a few hundred)
  List<Cell> cellQueue = [];

  // Initial grid
  for (double x = minX; x < maxX; x += cellSize) {
    for (double y = minY; y < maxY; y += cellSize) {
      cellQueue.add(Cell(x + h, y + h, h, polygon));
    }
  }

  // Take the best initial cell
  Cell bestCell = cellQueue.reduce((a, b) => a.d > b.d ? a : b);

  // Add the bounding box center as a fallback
  Cell bboxCell = Cell(minX + width / 2, minY + height / 2, 0, polygon);
  if (bboxCell.d > bestCell.d) bestCell = bboxCell;

  while (cellQueue.isNotEmpty) {
    // Pop the cell with the highest max potential
    cellQueue.sort();
    Cell cell = cellQueue.removeAt(0);

    // Update the best cell
    if (cell.d > bestCell.d) {
      bestCell = cell;
    }

    // Stop if this cell can't possibly contain a better center
    if (cell.max - bestCell.d <= precision) continue;

    // Subdivide cell into 4 quadrants
    h = cell.h / 2;
    cellQueue.add(Cell(cell.x - h, cell.y - h, h, polygon));
    cellQueue.add(Cell(cell.x + h, cell.y - h, h, polygon));
    cellQueue.add(Cell(cell.x - h, cell.y + h, h, polygon));
    cellQueue.add(Cell(cell.x + h, cell.y + h, h, polygon));
  }

  return PolylabelResult(Offset(bestCell.x, bestCell.y), bestCell.d);
}
