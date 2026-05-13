/// Pure, stateless functions for hex region boundary computation.
///
/// ## Algorithm Overview
///
/// Boundaries are represented as `Set<DirectedEdge>`. Each hex tile has 6
/// directed edges (one per side). When two adjacent tiles share a wall,
/// their directed edges are **opposites** of each other.
///
/// **Adding a tile to a region** generates 6 new edges. For each:
/// - If the set already contains the **opposite** edge (meaning an adjacent
///   tile is already in the region), both edges cancel out — the internal
///   wall dissolves.
/// - Otherwise, the edge is added as a new external boundary segment.
///
/// This gives **O(1) per edge** boundary updates, regardless of region size.
///
/// **Removing a tile** is the reverse: edges that exist in the set are removed;
/// edges that don't exist generate their opposite (re-creating the internal wall).
///
/// ## Hierarchy Propagation
///
/// When a tile is added/removed from a Layer 0 region, the boundary delta
/// must propagate upward to any parent regions in Layer 1, 2, etc. that
/// reference this region via [HexRegion.childRegions]. This is done
/// recursively by [propagateBoundaryAddition] and [propagateBoundaryRemoval].
library;

import 'package:hex_grid_mapmaker/models/hex_map.dart';
import 'package:hex_grid_mapmaker/models/hex_tile.dart';

/// Returns the 6 directed edges that form the complete boundary of a single tile.
Set<DirectedEdge> getTileBoundary(HexTile tile) =>
    {for (int d = 0; d < 6; d++) DirectedEdge(tile.q, tile.r, d)};

/// Computes the union of two boundary sets, dissolving shared internal walls.
///
/// For each edge in [addition]:
/// - If [current] contains the opposite edge → remove the opposite (wall dissolves).
/// - Otherwise → add the edge (new external boundary).
///
/// Returns a new set; [current] and [addition] are not modified.
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

/// Computes the difference of two boundary sets, re-creating internal walls.
///
/// For each edge in [removal]:
/// - If [current] contains the edge → remove it.
/// - Otherwise → add the opposite edge (wall re-appears).
///
/// Returns a new set; [current] and [removal] are not modified.
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

/// Recursively propagates a boundary addition upward through parent layers.
///
/// Starting from [layerIndex], looks for regions in Layer N+1 that list
/// [regionId] in their [childRegions]. Each matching parent has the [delta]
/// edges added to its cached boundary, then propagation continues to N+2, etc.
void propagateBoundaryAddition(
    HexMap map, String regionId, int layerIndex, Set<DirectedEdge> delta) {
  if (delta.isEmpty) return;
  final parentLayer = map.getLayer(layerIndex + 1);
  if (parentLayer == null) return;
  for (final region in parentLayer.regions) {
    if (region.childRegions?.contains(regionId) ?? false) {
      region.cachedBoundary =
          addBoundary(region.cachedBoundary ?? {}, delta);
      region.cachedLabelPosition = null; // Invalidate label cache.
      propagateBoundaryAddition(map, region.id, layerIndex + 1, delta);
    }
  }
}

/// Recursively propagates a boundary removal upward through parent layers.
///
/// Mirror of [propagateBoundaryAddition] — removes the [delta] edges from
/// each parent region's cached boundary.
void propagateBoundaryRemoval(
    HexMap map, String regionId, int layerIndex, Set<DirectedEdge> delta) {
  if (delta.isEmpty) return;
  final parentLayer = map.getLayer(layerIndex + 1);
  if (parentLayer == null) return;
  for (final region in parentLayer.regions) {
    if (region.childRegions?.contains(regionId) ?? false) {
      region.cachedBoundary =
          removeBoundary(region.cachedBoundary ?? {}, delta);
      region.cachedLabelPosition = null; // Invalidate label cache.
      propagateBoundaryRemoval(map, region.id, layerIndex + 1, delta);
    }
  }
}

/// Rebuilds every region's [cachedBoundary] from scratch.
///
/// Called after destructive operations (layer deletion, map load) where
/// incremental updates would be unreliable. Processes layers in order:
/// - Layer 0: boundary = union of all owned tile boundaries.
/// - Layer N: boundary = union of all child region boundaries from Layer N-1.
void recomputeAllBoundaries(HexMap map) {
  for (final layer in map.layers) {
    for (final region in layer.regions) {
      region.cachedBoundary = {};
      region.cachedLabelPosition = null;
      if (layer.index == 0) {
        // Layer 0: compute from concrete tiles.
        for (final tile in region.tiles ?? <HexTile>[]) {
          region.cachedBoundary =
              addBoundary(region.cachedBoundary!, getTileBoundary(tile));
        }
      } else if (region.childRegions != null) {
        // Layer N: aggregate child boundaries from the layer below.
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
