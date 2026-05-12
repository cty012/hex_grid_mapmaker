import 'package:hex_grid_mapmaker/models/hex_map.dart';
import 'package:hex_grid_mapmaker/models/hex_tile.dart';

/// Pure functions for boundary math — no state, fully testable.

Set<DirectedEdge> getTileBoundary(HexTile tile) =>
    {for (int d = 0; d < 6; d++) DirectedEdge(tile.q, tile.r, d)};

/// Union: dissolves internal walls via edge cancellation.
Set<DirectedEdge> addBoundary(
    Set<DirectedEdge> current, Set<DirectedEdge> addition) {
  final result = Set<DirectedEdge>.from(current);
  for (final edge in addition) {
    if (result.contains(edge.opposite)) {
      result.remove(edge.opposite);
    } else {
      result.add(edge);
    }
  }
  return result;
}

/// Difference: creates holes/dents by reversing edge cancellation.
Set<DirectedEdge> removeBoundary(
    Set<DirectedEdge> current, Set<DirectedEdge> removal) {
  final result = Set<DirectedEdge>.from(current);
  for (final edge in removal) {
    if (result.contains(edge)) {
      result.remove(edge);
    } else {
      result.add(edge.opposite);
    }
  }
  return result;
}

/// Recursively propagates added boundary upward through parent layers.
void propagateBoundaryAddition(
    HexMap map, String regionId, int layerIndex, Set<DirectedEdge> delta) {
  if (delta.isEmpty) return;
  final parentLayer = map.getLayer(layerIndex + 1);
  if (parentLayer == null) return;
  for (final region in parentLayer.regions) {
    if (region.childRegions?.contains(regionId) ?? false) {
      region.cachedBoundary =
          addBoundary(region.cachedBoundary ?? {}, delta);
      region.cachedLabelPosition = null;
      propagateBoundaryAddition(map, region.id, layerIndex + 1, delta);
    }
  }
}

/// Recursively propagates removed boundary upward through parent layers.
void propagateBoundaryRemoval(
    HexMap map, String regionId, int layerIndex, Set<DirectedEdge> delta) {
  if (delta.isEmpty) return;
  final parentLayer = map.getLayer(layerIndex + 1);
  if (parentLayer == null) return;
  for (final region in parentLayer.regions) {
    if (region.childRegions?.contains(regionId) ?? false) {
      region.cachedBoundary =
          removeBoundary(region.cachedBoundary ?? {}, delta);
      region.cachedLabelPosition = null;
      propagateBoundaryRemoval(map, region.id, layerIndex + 1, delta);
    }
  }
}

/// Rebuilds every region's cachedBoundary from scratch.
void recomputeAllBoundaries(HexMap map) {
  for (final layer in map.layers) {
    for (final region in layer.regions) {
      region.cachedBoundary = {};
      region.cachedLabelPosition = null;
      if (layer.index == 0) {
        for (final tile in region.tiles ?? <HexTile>[]) {
          region.cachedBoundary =
              addBoundary(region.cachedBoundary!, getTileBoundary(tile));
        }
      } else if (region.childRegions != null) {
        final childLayer = map.getLayer(layer.index - 1);
        if (childLayer == null) continue;
        for (final childId in region.childRegions!) {
          final child = childLayer.getRegion(childId);
          if (child?.cachedBoundary != null) {
            region.cachedBoundary =
                addBoundary(region.cachedBoundary!, child!.cachedBoundary!);
          }
        }
      }
    }
  }
}
