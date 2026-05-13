/// Reconstructs continuous Flutter [Path]s and vertex polygons from
/// unordered [DirectedEdge] sets.
///
/// ## Why This Is Needed
///
/// A region's boundary is stored as a flat `Set<DirectedEdge>` — an unordered
/// collection of individual edge segments. To **render** the boundary as a
/// continuous stroke or to run the **Polylabel** algorithm (which needs a
/// closed polygon ring), we must reconnect these edges into ordered loops.
///
/// ## Edge-Chaining Algorithm
///
/// Starting from an arbitrary unvisited edge:
/// 1. Mark it visited, compute its hex's pixel-space corners.
/// 2. Draw a line from corner[d] to corner[(d+1) % 6].
/// 3. Look for the **next** connected edge — prefer the same-tile next-direction
///    edge (opt1: continuing around the hex), otherwise jump to the
///    neighboring tile's edge that shares the same vertex (opt2: turning a corner).
/// 4. Repeat until no unvisited neighbor is found → close the loop.
/// 5. If unvisited edges remain, start a new loop (the region has disjoint components or holes).
library;

import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/enums.dart';
import 'package:hex_grid_mapmaker/models/hex_tile.dart';
import 'package:hex_grid_mapmaker/services/hex_geometry.dart' as geo;

/// Converts an unordered edge set into closed Flutter [Path]s for rendering.
///
/// Each returned path is a closed loop representing one contiguous boundary
/// segment. A region with disjoint tiles will produce multiple paths.
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

      // Option 1: continue around the same hex (next edge on this tile).
      final opt1 = DirectedEdge(current.q, current.r, next);
      // Option 2: jump to the neighboring tile that shares this vertex.
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

/// Converts an unordered edge set into closed vertex polygons for Polylabel.
///
/// Similar to [buildBoundaryPaths] but returns raw `List<Offset>` rings
/// instead of Flutter Paths. These rings are fed to the Polylabel algorithm
/// to compute the Pole of Inaccessibility for optimal label placement.
///
/// Multiple rings may be returned for multi-component regions. The caller
/// must classify them as outer boundaries or holes using [signedArea].
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

/// Computes the signed area of a polygon ring using the Shoelace formula.
///
/// - **Positive** area → counterclockwise winding (outer boundary).
/// - **Negative** area → clockwise winding (hole).
///
/// The absolute value gives the geometric area; the sign determines whether
/// the ring is an outer boundary or a hole, which is needed to correctly
/// construct multi-ring polygons for the Polylabel algorithm.
double signedArea(List<Offset> ring) {
  double area = 0;
  for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    area += (ring[j].dx * ring[i].dy) - (ring[i].dx * ring[j].dy);
  }
  return area / 2;
}

/// Determines if a point lies inside a polygon using the ray casting algorithm.
///
/// Casts a horizontal ray from [p] to the right and counts how many polygon
/// edges it crosses. An odd count means inside, even means outside.
///
/// Used to assign hole rings to their enclosing outer boundary when building
/// multi-ring polygons for Polylabel.
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
