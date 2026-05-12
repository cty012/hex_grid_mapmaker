import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/hex_map.dart';
import 'package:hex_grid_mapmaker/models/hex_region.dart';
import 'package:hex_grid_mapmaker/models/hex_tile.dart';
import 'package:hex_grid_mapmaker/services/boundary_service.dart' as boundary;

/// Owns the HexMap and all data-mutating operations.
/// All mutations go through this class — UI never directly modifies models.
class MapState extends ChangeNotifier {
  HexMap hexMap = HexMap();

  MapState() {
    _ensureLayerExists(0);
  }

  // ── Layer Operations ──────────────────────────────────────────────

  void _ensureLayerExists(int index) {
    if (hexMap.getLayer(index) == null) {
      hexMap.layers.add(HexLayer(index: index));
      hexMap.layers.sort((a, b) => a.index.compareTo(b.index));
    }
  }

  /// Creates a new layer and returns its index.
  int addLayer() {
    final maxIndex = hexMap.layers.fold(-1, (m, l) => l.index > m ? l.index : m);
    final newIndex = maxIndex + 1;
    _ensureLayerExists(newIndex);
    notifyListeners();
    return newIndex;
  }

  void deleteLayer(int targetIndex) {
    final targetLayer = hexMap.getLayer(targetIndex);
    if (targetLayer == null) return;

    if (targetIndex == 0) {
      if (hexMap.layers.length == 1) {
        targetLayer.regions.clear();
      } else {
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

  void ensureLayerExists(int index) {
    _ensureLayerExists(index);
  }

  // ── Region Operations ─────────────────────────────────────────────

  /// Creates a new region and returns its auto-generated ID.
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

  /// Returns error message on failure, null on success.
  String? updateRegionId(String oldId, String newId, int layerIndex) {
    if (newId.trim().isEmpty) return 'ID cannot be empty';
    if (oldId == newId) return null;
    if (hexMap.isIdInUse(newId)) return 'ID already in use';

    final layer = hexMap.getLayer(layerIndex);
    if (layer == null) return 'Layer not found';
    final region = layer.getRegion(oldId);
    if (region == null) return 'Region not found';

    region.id = newId;

    // Cascade rename into parent layer references.
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

  void setRegionName(int layerIndex, String regionId, String name) {
    final region = hexMap.getLayer(layerIndex)?.getRegion(regionId);
    if (region == null) return;
    region.name = name;
    notifyListeners();
  }

  // ── Tile Operations ───────────────────────────────────────────────

  void addTileToRegion(HexTile tile, int layerIndex, String regionId) {
    if (layerIndex == 0) {
      _addTileLayer0(tile, layerIndex, regionId);
    } else {
      _addTileLayerN(tile, layerIndex, regionId);
    }
  }

  void _addTileLayer0(HexTile tile, int layerIndex, String regionId) {
    final layer = hexMap.getLayer(layerIndex);
    if (layer == null) return;
    final tileBoundary = boundary.getTileBoundary(tile);

    // Remove tile from any other region first.
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

  void _addTileLayerN(HexTile tile, int layerIndex, String regionId) {
    final childRegion = getRegionAtTile(tile, layerIndex - 1);
    if (childRegion == null) return;
    final layer = hexMap.getLayer(layerIndex);
    if (layer == null) return;
    final childBoundary = childRegion.cachedBoundary ?? {};

    // Remove from other regions first.
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

  HexRegion? getRegionAtTile(HexTile tile, int layerIndex) {
    final layer = hexMap.getLayer(layerIndex);
    if (layer == null) return null;
    for (final region in layer.regions) {
      if (getTilesForRegion(region, layerIndex).contains(tile)) return region;
    }
    return null;
  }

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

  void loadMap(HexMap map) {
    hexMap = map;
    if (hexMap.layers.isEmpty) _ensureLayerExists(0);
    hexMap.layers.sort((a, b) => a.index.compareTo(b.index));
    boundary.recomputeAllBoundaries(hexMap);
    notifyListeners();
  }

  void forceUpdate() => notifyListeners();

  // ── Helpers ───────────────────────────────────────────────────────

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
