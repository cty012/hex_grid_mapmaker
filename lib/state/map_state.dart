import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/hex_map.dart';
import 'package:hex_grid_mapmaker/models/hex_region.dart';
import 'package:hex_grid_mapmaker/models/hex_tile.dart';
import 'package:hex_grid_mapmaker/services/boundary_service.dart' as boundary;

/// The central data state for the Hex Grid Mapmaker.
///
/// Owns the [HexMap] and exposes all data-mutating operations as methods.
/// UI widgets should **never** directly modify model fields — they call
/// methods on this class instead, which ensures:
///
/// 1. **Boundary caches** are kept in sync (via [boundary_service.dart]).
/// 2. **Cross-layer references** are updated when IDs change or regions are deleted.
/// 3. **Listeners are notified** so the UI rebuilds with fresh data.
///
/// Provided as a [ChangeNotifierProvider] in `main.dart`. Paired with
/// [EditorState] which handles UI-only concerns (tool selection, etc.).
class MapState extends ChangeNotifier {
  /// The global map data structure. Contains all layers, regions, and tiles.
  HexMap hexMap = HexMap();

  /// Initializes with a single empty Layer 0.
  MapState() {
    _ensureLayerExists(0);
  }

  // ── Layer Operations ──────────────────────────────────────────────

  /// Creates Layer [index] if it doesn't already exist, maintaining sort order.
  void _ensureLayerExists(int index) {
    if (hexMap.getLayer(index) == null) {
      hexMap.layers.add(HexLayer(index: index));
      hexMap.layers.sort((a, b) => a.index.compareTo(b.index));
    }
  }

  /// Creates a new layer at the next available index and returns it.
  ///
  /// The caller (usually [HierarchyPanel]) should then call
  /// `editorState.setActiveLayer(newIndex)` to switch to it.
  int addLayer() {
    final maxIndex = hexMap.layers.fold(-1, (m, l) => l.index > m ? l.index : m);
    final newIndex = maxIndex + 1;
    _ensureLayerExists(newIndex);
    notifyListeners();
    return newIndex;
  }

  /// Deletes the layer at [targetIndex] and handles hierarchy remapping.
  ///
  /// ## Layer 0 Deletion
  /// If Layer 0 is the only layer, its regions are simply cleared.
  /// If other layers exist, Layer 1's regions "absorb" their child regions'
  /// tiles: for each Layer 1 region, all tiles from its child regions in
  /// Layer 0 are collected into [HexRegion.tiles], and [childRegions] is
  /// cleared. Layer 1 effectively becomes the new Layer 0.
  ///
  /// ## Layer N Deletion (N > 0)
  /// Parent regions in Layer N+1 have their [childRegions] remapped: instead
  /// of pointing to regions in Layer N, they now point directly to the
  /// deleted layer's regions' children (one level deeper).
  ///
  /// After deletion, all layer indices above [targetIndex] are decremented
  /// and boundaries are fully recomputed.
  void deleteLayer(int targetIndex) {
    final targetLayer = hexMap.getLayer(targetIndex);
    if (targetLayer == null) return;

    if (targetIndex == 0) {
      if (hexMap.layers.length == 1) {
        // Only layer — just clear its regions.
        targetLayer.regions.clear();
      } else {
        // Promote Layer 1 to the new base layer by flattening child references.
        final layer1 = hexMap.getLayer(1);
        if (layer1 != null) {
          for (final region in layer1.regions) {
            final allTiles = <HexTile>{};
            for (final childId in region.childRegions ?? <String>[]) {
              final child = targetLayer.getRegion(childId);
              if (child?.tiles != null) allTiles.addAll(child!.tiles!);
            }
            region.tiles = allTiles.toList();
            region.childRegions = null;
          }
        }
        hexMap.layers.remove(targetLayer);
      }
    } else {
      // Remap parent layer's child references to skip the deleted layer.
      final parentLayer = hexMap.getLayer(targetIndex + 1);
      if (parentLayer != null) {
        for (final region in parentLayer.regions) {
          final newChildren = <String>{};
          for (final childId in region.childRegions ?? <String>[]) {
            final child = targetLayer.getRegion(childId);
            if (child?.childRegions != null) {
              newChildren.addAll(child!.childRegions!);
            }
          }
          region.childRegions = newChildren.toList();
        }
      }
      hexMap.layers.remove(targetLayer);
    }

    // Shift indices down for layers above the deleted one.
    if (!(targetIndex == 0 && hexMap.layers.length == 1 && hexMap.layers[0].index == 0)) {
      for (final layer in hexMap.layers) {
        if (layer.index > targetIndex) layer.index--;
      }
    }

    boundary.recomputeAllBoundaries(hexMap);
    notifyListeners();
  }

  /// Public wrapper for [_ensureLayerExists]. Used by [EditorScreen] during
  /// map loading to guarantee the active layer exists.
  void ensureLayerExists(int index) {
    _ensureLayerExists(index);
  }

  // ── Region Operations ─────────────────────────────────────────────

  /// Creates a new region in [layerIndex] with the given [name].
  ///
  /// Auto-generates a unique numeric ID (e.g. "1", "2", "3") by scanning
  /// all existing region IDs. Layer 0 regions get an empty [tiles] list;
  /// Layer N regions get an empty [childRegions] list.
  ///
  /// Returns the generated ID so the caller can immediately select it.
  String addRegion(int layerIndex, String name) {
    _ensureLayerExists(layerIndex);
    final newId = _nextAvailableId();
    final layer = hexMap.getLayer(layerIndex)!;
    layer.regions.add(HexRegion(
      id: newId,
      name: name,
      tiles: layerIndex == 0 ? [] : null,
      childRegions: layerIndex > 0 ? [] : null,
    ));
    notifyListeners();
    return newId;
  }

  /// Removes a region and propagates the boundary removal to parent layers.
  ///
  /// Also cleans up parent layer references: any region in Layer N+1 that
  /// had [id] in its [childRegions] list will have it removed.
  void deleteRegion(String id, int layerIndex) {
    final layer = hexMap.getLayer(layerIndex);
    if (layer == null) return;
    final region = layer.getRegion(id);
    if (region == null) return;

    layer.regions.remove(region);
    boundary.propagateBoundaryRemoval(
        hexMap, id, layerIndex, region.cachedBoundary ?? {});

    // Remove from parent layer's child lists.
    final parentLayer = hexMap.getLayer(layerIndex + 1);
    if (parentLayer != null) {
      for (final r in parentLayer.regions) {
        r.childRegions?.remove(id);
      }
    }
    notifyListeners();
  }

  /// Renames a region's ID, cascading the change to parent layer references.
  ///
  /// Returns an error message string on failure, or null on success.
  /// Validates that the new ID is non-empty and not already in use.
  String? updateRegionId(String oldId, String newId, int layerIndex) {
    if (newId.trim().isEmpty) return 'ID cannot be empty';
    if (oldId == newId) return null;
    if (hexMap.isIdInUse(newId)) return 'ID already in use';

    final layer = hexMap.getLayer(layerIndex);
    if (layer == null) return 'Layer not found';
    final region = layer.getRegion(oldId);
    if (region == null) return 'Region not found';

    region.id = newId;

    // Cascade rename into parent layer child references.
    final parentLayer = hexMap.getLayer(layerIndex + 1);
    if (parentLayer != null) {
      for (final parent in parentLayer.regions) {
        final idx = parent.childRegions?.indexOf(oldId) ?? -1;
        if (idx >= 0) parent.childRegions![idx] = newId;
      }
    }

    notifyListeners();
    return null;
  }

  /// Updates a region's display name.
  void setRegionName(int layerIndex, String regionId, String name) {
    final region = hexMap.getLayer(layerIndex)?.getRegion(regionId);
    if (region == null) return;
    region.name = name;
    notifyListeners();
  }

  // ── Tile Operations ───────────────────────────────────────────────

  /// Adds a tile to the specified region, handling both Layer 0 and Layer N.
  ///
  /// Delegates to [_addTileLayer0] for direct tile placement or
  /// [_addTileLayerN] for child-region-based assignment.
  void addTileToRegion(HexTile tile, int layerIndex, String regionId) {
    if (layerIndex == 0) {
      _addTileLayer0(tile, layerIndex, regionId);
    } else {
      _addTileLayerN(tile, layerIndex, regionId);
    }
  }

  /// Layer 0: adds a concrete hex tile to a region.
  ///
  /// If the tile already belongs to another region, it is removed first
  /// (tiles can only belong to one region at a time). Boundary caches are
  /// updated incrementally and propagated upward.
  void _addTileLayer0(HexTile tile, int layerIndex, String regionId) {
    final layer = hexMap.getLayer(layerIndex);
    if (layer == null) return;
    final tileBoundary = boundary.getTileBoundary(tile);

    // Remove tile from any other region first (exclusive ownership).
    for (final region in layer.regions) {
      if (region.id != regionId &&
          region.tiles != null &&
          region.tiles!.contains(tile)) {
        region.tiles!.remove(tile);
        region.cachedBoundary =
            boundary.removeBoundary(region.cachedBoundary ?? {}, tileBoundary);
        region.cachedLabelPosition = null;
        boundary.propagateBoundaryRemoval(
            hexMap, region.id, layerIndex, tileBoundary);
      }
    }

    // Add to target region.
    final target = layer.getRegion(regionId);
    if (target == null) return;
    target.tiles ??= [];
    if (!target.tiles!.contains(tile)) {
      target.tiles!.add(tile);
      target.cachedBoundary =
          boundary.addBoundary(target.cachedBoundary ?? {}, tileBoundary);
      target.cachedLabelPosition = null;
      boundary.propagateBoundaryAddition(
          hexMap, regionId, layerIndex, tileBoundary);
      notifyListeners();
    }
  }

  /// Layer N: "draws" on a higher layer by assigning child regions.
  ///
  /// Clicking a tile on Layer N finds the Layer N-1 region that contains
  /// that tile, then adds that child region's ID to the target Layer N region's
  /// [childRegions] list. Boundary caches are updated with the child's
  /// full boundary.
  void _addTileLayerN(HexTile tile, int layerIndex, String regionId) {
    final childRegion = getRegionAtTile(tile, layerIndex - 1);
    if (childRegion == null) return;
    final layer = hexMap.getLayer(layerIndex);
    if (layer == null) return;
    final childBoundary = childRegion.cachedBoundary ?? {};

    // Remove from other regions first (exclusive child ownership).
    for (final region in layer.regions) {
      if (region.id != regionId &&
          region.childRegions != null &&
          region.childRegions!.contains(childRegion.id)) {
        region.childRegions!.remove(childRegion.id);
        region.cachedBoundary =
            boundary.removeBoundary(region.cachedBoundary ?? {}, childBoundary);
        region.cachedLabelPosition = null;
        boundary.propagateBoundaryRemoval(
            hexMap, region.id, layerIndex, childBoundary);
      }
    }

    // Add to target region.
    final target = layer.getRegion(regionId);
    if (target == null) return;
    target.childRegions ??= [];
    if (!target.childRegions!.contains(childRegion.id)) {
      target.childRegions!.add(childRegion.id);
      target.cachedBoundary =
          boundary.addBoundary(target.cachedBoundary ?? {}, childBoundary);
      target.cachedLabelPosition = null;
      boundary.propagateBoundaryAddition(
          hexMap, regionId, layerIndex, childBoundary);
      notifyListeners();
    }
  }

  /// Erases a tile from whichever region owns it at [layerIndex].
  ///
  /// For Layer 0, removes the concrete tile. For Layer N, removes the
  /// child region reference (the child region itself is not deleted).
  void removeTile(HexTile tile, int layerIndex) {
    final layer = hexMap.getLayer(layerIndex);
    if (layer == null) return;
    bool removed = false;

    if (layerIndex == 0) {
      final tileBoundary = boundary.getTileBoundary(tile);
      for (final region in layer.regions) {
        if (region.tiles != null && region.tiles!.contains(tile)) {
          region.tiles!.remove(tile);
          region.cachedBoundary = boundary.removeBoundary(
              region.cachedBoundary ?? {}, tileBoundary);
          region.cachedLabelPosition = null;
          boundary.propagateBoundaryRemoval(
              hexMap, region.id, layerIndex, tileBoundary);
          removed = true;
        }
      }
    } else {
      final childRegion = getRegionAtTile(tile, layerIndex - 1);
      if (childRegion == null) return;
      final childBoundary = childRegion.cachedBoundary ?? {};
      for (final region in layer.regions) {
        if (region.childRegions != null &&
            region.childRegions!.contains(childRegion.id)) {
          region.childRegions!.remove(childRegion.id);
          region.cachedBoundary = boundary.removeBoundary(
              region.cachedBoundary ?? {}, childBoundary);
          region.cachedLabelPosition = null;
          boundary.propagateBoundaryRemoval(
              hexMap, region.id, layerIndex, childBoundary);
          removed = true;
        }
      }
    }

    if (removed) notifyListeners();
  }

  // ── Queries ───────────────────────────────────────────────────────

  /// Finds which region at [layerIndex] contains the given [tile].
  ///
  /// For Layer 0, checks region.tiles directly. For higher layers,
  /// recursively resolves child regions down to Layer 0 tiles.
  /// Returns null if no region contains the tile.
  HexRegion? getRegionAtTile(HexTile tile, int layerIndex) {
    final layer = hexMap.getLayer(layerIndex);
    if (layer == null) return null;
    for (final region in layer.regions) {
      if (getTilesForRegion(region, layerIndex).contains(tile)) return region;
    }
    return null;
  }

  /// Returns all concrete Layer 0 tiles that belong to a region.
  ///
  /// For Layer 0 regions, returns [tiles] directly. For Layer N regions,
  /// recursively collects tiles from all descendant child regions.
  List<HexTile> getTilesForRegion(HexRegion region, int layerIndex) {
    if (layerIndex == 0) return region.tiles ?? [];
    final childLayer = hexMap.getLayer(layerIndex - 1);
    if (childLayer == null) return [];
    final allTiles = <HexTile>[];
    for (final childId in region.childRegions ?? <String>[]) {
      final child = childLayer.getRegion(childId);
      if (child != null) {
        allTiles.addAll(getTilesForRegion(child, layerIndex - 1));
      }
    }
    return allTiles;
  }

  // ── I/O ───────────────────────────────────────────────────────────

  /// Replaces the current map with a loaded one.
  ///
  /// Ensures at least Layer 0 exists, sorts layers, and fully recomputes
  /// all boundary caches (since serialized maps don't store cached data).
  void loadMap(HexMap map) {
    hexMap = map;
    if (hexMap.layers.isEmpty) _ensureLayerExists(0);
    hexMap.layers.sort((a, b) => a.index.compareTo(b.index));
    boundary.recomputeAllBoundaries(hexMap);
    notifyListeners();
  }

  /// Triggers a UI rebuild without modifying data.
  ///
  /// Used when the UI (e.g. PropertiesPanel) modifies region attributes
  /// directly through convenience methods and needs the painter to redraw.
  void forceUpdate() => notifyListeners();

  // ── Helpers ───────────────────────────────────────────────────────

  /// Generates the next available numeric ID by scanning all existing regions.
  ///
  /// Starts at "1" and increments until an unused ID is found. Non-numeric
  /// IDs (e.g. user-renamed IDs like "capital") are ignored in the scan.
  String _nextAvailableId() {
    final usedIds = <int>{};
    for (final layer in hexMap.layers) {
      for (final region in layer.regions) {
        final n = int.tryParse(region.id);
        if (n != null && n > 0) usedIds.add(n);
      }
    }
    int next = 1;
    while (usedIds.contains(next)) {
      next++;
    }
    return next.toString();
  }
}
