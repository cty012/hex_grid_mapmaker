import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/enums.dart';
import 'package:hex_grid_mapmaker/models/hex_tile.dart';
import 'package:hex_grid_mapmaker/services/hex_geometry.dart' as geo;

/// Reconstructs continuous Paths/Polygons from unordered DirectedEdge sets.

List<Path> buildBoundaryPaths(
    Set<DirectedEdge> boundary, MapOrientation orientation, double hexSize) {
  final unvisited = Set<DirectedEdge>.from(boundary);
  final paths = <Path>[];

  while (unvisited.isNotEmpty) {
    final path = Path();
    var current = unvisited.first;
    bool first = true;

    while (true) {
      unvisited.remove(current);
      final center = geo.hexToPixel(
          orientation, hexSize, HexTile(q: current.q, r: current.r));
      final corners = geo.hexCorners(orientation, hexSize, center);

      if (first) {
        path.moveTo(corners[current.d].dx, corners[current.d].dy);
        first = false;
      }
      final next = (current.d + 1) % 6;
      path.lineTo(corners[next].dx, corners[next].dy);

      final opt1 = DirectedEdge(current.q, current.r, next);
      const dq = [1, 0, -1, -1, 0, 1];
      const dr = [0, 1, 1, 0, -1, -1];
      final opt2 = DirectedEdge(
          current.q + dq[next], current.r + dr[next], (current.d + 5) % 6);

      if (unvisited.contains(opt1)) {
        current = opt1;
      } else if (unvisited.contains(opt2)) {
        current = opt2;
      } else {
        path.close();
        break;
      }
    }
    paths.add(path);
  }
  return paths;
}

List<List<Offset>> buildBoundaryPolygons(
    Set<DirectedEdge> boundary, MapOrientation orientation, double hexSize) {
  final unvisited = Set<DirectedEdge>.from(boundary);
  final polygons = <List<Offset>>[];

  while (unvisited.isNotEmpty) {
    final polygon = <Offset>[];
    var current = unvisited.first;
    bool first = true;

    while (true) {
      unvisited.remove(current);
      final center = geo.hexToPixel(
          orientation, hexSize, HexTile(q: current.q, r: current.r));
      final corners = geo.hexCorners(orientation, hexSize, center);

      if (first) {
        polygon.add(corners[current.d]);
        first = false;
      }
      final next = (current.d + 1) % 6;
      polygon.add(corners[next]);

      final opt1 = DirectedEdge(current.q, current.r, next);
      const dq = [1, 0, -1, -1, 0, 1];
      const dr = [0, 1, 1, 0, -1, -1];
      final opt2 = DirectedEdge(
          current.q + dq[next], current.r + dr[next], (current.d + 5) % 6);

      if (unvisited.contains(opt1)) {
        current = opt1;
      } else if (unvisited.contains(opt2)) {
        current = opt2;
      } else {
        break;
      }
    }
    polygons.add(polygon);
  }
  return polygons;
}

/// Shoelace formula. Sign indicates winding order (outer vs hole).
double signedArea(List<Offset> ring) {
  double area = 0;
  for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    area += (ring[j].dx * ring[i].dy) - (ring[i].dx * ring[j].dy);
  }
  return area / 2;
}

/// Ray casting point-in-polygon test.
bool pointInPolygon(Offset p, List<Offset> polygon) {
  bool inside = false;
  for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    if ((polygon[i].dy > p.dy) != (polygon[j].dy > p.dy) &&
        (p.dx <
            (polygon[j].dx - polygon[i].dx) *
                    (p.dy - polygon[i].dy) /
                    (polygon[j].dy - polygon[i].dy) +
                polygon[i].dx)) {
      inside = !inside;
    }
  }
  return inside;
}
