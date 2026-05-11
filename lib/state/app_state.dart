import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/hex_models.dart';

class AppState extends ChangeNotifier {
  HexMap hexMap = HexMap();

  String activeTool = 'select'; // 'select', 'draw', 'erase'
  String? activeRegionId;

  int activeLayerIndex = 0;

  bool showGrid = true;
  String labelDisplay = 'None'; // 'None', 'ID', 'Name'

  AppState() {
    _ensureLayerExists(0);
  }

  void _ensureLayerExists(int index) {
    if (!hexMap.layers.any((l) => l.index == index)) {
      hexMap.layers.add(HexLayer(index: index, regions: []));
      hexMap.layers.sort((a, b) => a.index.compareTo(b.index));
    }
  }

  void addLayer() {
    int maxIndex = hexMap.layers.fold(
      -1,
      (max, l) => l.index > max ? l.index : max,
    );
    _ensureLayerExists(maxIndex + 1);
    setActiveLayer(maxIndex + 1);
  }

  void deleteLayer() {
    if (activeLayerIndex == 0) return; // Cannot delete layer 0
    hexMap.layers.removeWhere((l) => l.index == activeLayerIndex);
    setActiveLayer(activeLayerIndex - 1);
  }

  void setActiveLayer(int index) {
    _ensureLayerExists(index);
    activeLayerIndex = index;
    activeRegionId = null;
    notifyListeners();
  }

  HexLayer get activeLayer {
    return hexMap.layers.firstWhere((l) => l.index == activeLayerIndex);
  }

  void loadMap(HexMap map) {
    hexMap = map;
    activeRegionId = null;
    if (hexMap.layers.isEmpty) {
      _ensureLayerExists(0);
    }
    hexMap.layers.sort((a, b) => a.index.compareTo(b.index));
    _recomputeAllBoundaries();
    activeLayerIndex = 0;
    notifyListeners();
  }

  Set<DirectedEdge> _getTileBoundary(HexTile tile) {
    return {
      DirectedEdge(tile.q, tile.r, 0),
      DirectedEdge(tile.q, tile.r, 1),
      DirectedEdge(tile.q, tile.r, 2),
      DirectedEdge(tile.q, tile.r, 3),
      DirectedEdge(tile.q, tile.r, 4),
      DirectedEdge(tile.q, tile.r, 5),
    };
  }

  Set<DirectedEdge> addBoundary(
    Set<DirectedEdge> current,
    Set<DirectedEdge> newBoundary,
  ) {
    Set<DirectedEdge> result = Set.from(current);
    for (var edge in newBoundary) {
      if (result.contains(edge.opposite)) {
        result.remove(edge.opposite);
      } else {
        result.add(edge);
      }
    }
    return result;
  }

  Set<DirectedEdge> removeBoundary(
    Set<DirectedEdge> current,
    Set<DirectedEdge> rmBoundary,
  ) {
    Set<DirectedEdge> result = Set.from(current);
    for (var edge in rmBoundary) {
      if (result.contains(edge)) {
        result.remove(edge);
      } else {
        result.add(edge.opposite);
      }
    }
    return result;
  }

  void _propagateBoundaryAddition(
    String regionId,
    int layerIndex,
    Set<DirectedEdge> boundaryAdded,
  ) {
    if (boundaryAdded.isEmpty) return;
    try {
      final parentLayer = hexMap.layers.firstWhere(
        (l) => l.index == layerIndex + 1,
      );
      for (var pRegion in parentLayer.regions) {
        if (pRegion.childRegions?.contains(regionId) ?? false) {
          pRegion.cachedBoundary = addBoundary(
            pRegion.cachedBoundary ?? {},
            boundaryAdded,
          );
          pRegion.cachedLabelPosition = null;
          _propagateBoundaryAddition(pRegion.id, layerIndex + 1, boundaryAdded);
        }
      }
    } catch (_) {}
  }

  void _propagateBoundaryRemoval(
    String regionId,
    int layerIndex,
    Set<DirectedEdge> boundaryRemoved,
  ) {
    if (boundaryRemoved.isEmpty) return;
    try {
      final parentLayer = hexMap.layers.firstWhere(
        (l) => l.index == layerIndex + 1,
      );
      for (var pRegion in parentLayer.regions) {
        if (pRegion.childRegions?.contains(regionId) ?? false) {
          pRegion.cachedBoundary = removeBoundary(
            pRegion.cachedBoundary ?? {},
            boundaryRemoved,
          );
          pRegion.cachedLabelPosition = null;
          _propagateBoundaryRemoval(
            pRegion.id,
            layerIndex + 1,
            boundaryRemoved,
          );
        }
      }
    } catch (_) {}
  }

  void _recomputeAllBoundaries() {
    for (var layer in hexMap.layers) {
      for (var region in layer.regions) {
        region.cachedBoundary = {};
        region.cachedLabelPosition = null;
        if (layer.index == 0) {
          if (region.tiles != null) {
            for (var tile in region.tiles!) {
              region.cachedBoundary = addBoundary(
                region.cachedBoundary!,
                _getTileBoundary(tile),
              );
            }
          }
        } else {
          if (region.childRegions != null) {
            try {
              final childLayer = hexMap.layers.firstWhere(
                (l) => l.index == layer.index - 1,
              );
              for (var childId in region.childRegions!) {
                try {
                  final child = childLayer.regions.firstWhere(
                    (r) => r.id == childId,
                  );
                  if (child.cachedBoundary != null) {
                    region.cachedBoundary = addBoundary(
                      region.cachedBoundary!,
                      child.cachedBoundary!,
                    );
                  }
                } catch (_) {}
              }
            } catch (_) {}
          }
        }
      }
    }
  }

  void setOrientation(String orientation) {
    hexMap.orientation = orientation;
    notifyListeners();
  }

  void setTool(String tool) {
    activeTool = tool;
    notifyListeners();
  }

  void setActiveRegion(String? regionId) {
    activeRegionId = regionId;
    notifyListeners();
  }

  void setShowGrid(bool value) {
    showGrid = value;
    notifyListeners();
  }

  void setLabelDisplay(String value) {
    labelDisplay = value;
    notifyListeners();
  }

  void addTileToActiveRegion(HexTile tile) {
    if (activeRegionId == null) return;

    if (activeLayerIndex == 0) {
      Set<DirectedEdge> tileBoundary = _getTileBoundary(tile);
      // Remove tile from any other region in layer 0
      for (var region in activeLayer.regions) {
        if (region.tiles != null &&
            region.id != activeRegionId &&
            region.tiles!.contains(tile)) {
          region.tiles!.remove(tile);
          region.cachedBoundary = removeBoundary(
            region.cachedBoundary ?? {},
            tileBoundary,
          );
          region.cachedLabelPosition = null;
          _propagateBoundaryRemoval(region.id, activeLayerIndex, tileBoundary);
        }
      }

      // Add to active region
      var region = activeRegion;
      if (region != null) {
        region.tiles ??= [];
        if (!region.tiles!.contains(tile)) {
          region.tiles!.add(tile);
          region.cachedBoundary = addBoundary(
            region.cachedBoundary ?? {},
            tileBoundary,
          );
          region.cachedLabelPosition = null;
          _propagateBoundaryAddition(region.id, activeLayerIndex, tileBoundary);
          notifyListeners();
        }
      }
    } else {
      // Layer N > 0
      // Find the region in Layer N-1 that this tile belongs to
      final childRegion = getRegionAtTileForLayer(tile, activeLayerIndex - 1);
      if (childRegion != null) {
        Set<DirectedEdge> childBoundary = childRegion.cachedBoundary ?? {};
        // Remove childRegion from any other region in current layer
        for (var region in activeLayer.regions) {
          if (region.childRegions != null &&
              region.id != activeRegionId &&
              region.childRegions!.contains(childRegion.id)) {
            region.childRegions!.remove(childRegion.id);
            region.cachedBoundary = removeBoundary(
              region.cachedBoundary ?? {},
              childBoundary,
            );
            region.cachedLabelPosition = null;
            _propagateBoundaryRemoval(
              region.id,
              activeLayerIndex,
              childBoundary,
            );
          }
        }

        // Add to active region
        var region = activeRegion;
        if (region != null) {
          region.childRegions ??= [];
          if (!region.childRegions!.contains(childRegion.id)) {
            region.childRegions!.add(childRegion.id);
            region.cachedBoundary = addBoundary(
              region.cachedBoundary ?? {},
              childBoundary,
            );
            region.cachedLabelPosition = null;
            _propagateBoundaryAddition(
              region.id,
              activeLayerIndex,
              childBoundary,
            );
            notifyListeners();
          }
        }
      }
    }
  }

  void removeTile(HexTile tile) {
    bool removed = false;

    if (activeLayerIndex == 0) {
      Set<DirectedEdge> tileBoundary = _getTileBoundary(tile);
      for (var region in activeLayer.regions) {
        if (region.tiles != null && region.tiles!.contains(tile)) {
          region.tiles!.remove(tile);
          region.cachedBoundary = removeBoundary(
            region.cachedBoundary ?? {},
            tileBoundary,
          );
          region.cachedLabelPosition = null;
          _propagateBoundaryRemoval(region.id, activeLayerIndex, tileBoundary);
          removed = true;
        }
      }
    } else {
      final childRegion = getRegionAtTileForLayer(tile, activeLayerIndex - 1);
      if (childRegion != null) {
        Set<DirectedEdge> childBoundary = childRegion.cachedBoundary ?? {};
        for (var region in activeLayer.regions) {
          if (region.childRegions != null &&
              region.childRegions!.contains(childRegion.id)) {
            region.childRegions!.remove(childRegion.id);
            region.cachedBoundary = removeBoundary(
              region.cachedBoundary ?? {},
              childBoundary,
            );
            region.cachedLabelPosition = null;
            _propagateBoundaryRemoval(
              region.id,
              activeLayerIndex,
              childBoundary,
            );
            removed = true;
          }
        }
      }
    }

    if (removed) {
      notifyListeners();
    }
  }

  HexRegion? getRegionAtTileForLayer(HexTile tile, int layerIndex) {
    try {
      final layer = hexMap.layers.firstWhere((l) => l.index == layerIndex);
      for (var region in layer.regions) {
        final tiles = getTilesForRegion(region, layerIndex);
        if (tiles.contains(tile)) return region;
      }
    } catch (_) {}
    return null;
  }

  HexRegion? getRegionAtTile(HexTile tile) {
    return getRegionAtTileForLayer(tile, activeLayerIndex);
  }

  List<HexTile> getTilesForRegion(HexRegion region, int layerIndex) {
    if (layerIndex == 0) {
      return region.tiles ?? [];
    } else {
      List<HexTile> allTiles = [];
      if (region.childRegions != null) {
        try {
          final childLayer = hexMap.layers.firstWhere(
            (l) => l.index == layerIndex - 1,
          );
          for (var childId in region.childRegions!) {
            try {
              final childRegion = childLayer.regions.firstWhere(
                (r) => r.id == childId,
              );
              allTiles.addAll(getTilesForRegion(childRegion, layerIndex - 1));
            } catch (_) {}
          }
        } catch (_) {}
      }
      return allTiles;
    }
  }

  void addRegion(String name) {
    final newId = 'region_${DateTime.now().millisecondsSinceEpoch}';
    activeLayer.regions.add(
      HexRegion(
        id: newId,
        name: name,
        tiles: activeLayerIndex == 0 ? [] : null,
        childRegions: activeLayerIndex > 0 ? [] : null,
      ),
    );
    activeRegionId = newId;
    notifyListeners();
  }

  void deleteRegion(String id) {
    var regionToRemove = activeLayer.regions.firstWhere(
      (r) => r.id == id,
      orElse: () => HexRegion(id: '', name: ''),
    );
    if (regionToRemove.id.isNotEmpty) {
      activeLayer.regions.remove(regionToRemove);
      if (activeRegionId == id) {
        activeRegionId = null;
      }
      // Remove this region's boundary from all parents
      _propagateBoundaryRemoval(
        regionToRemove.id,
        activeLayerIndex,
        regionToRemove.cachedBoundary ?? {},
      );

      // Also remove this region from any parent layer child lists
      try {
        final parentLayer = hexMap.layers.firstWhere(
          (l) => l.index == activeLayerIndex + 1,
        );
        for (var r in parentLayer.regions) {
          if (r.childRegions?.contains(id) ?? false) {
            r.childRegions!.remove(id);
          }
        }
      } catch (_) {}
      notifyListeners();
    }
  }

  HexRegion? get activeRegion {
    if (activeRegionId == null) return null;
    try {
      return activeLayer.regions.firstWhere((r) => r.id == activeRegionId);
    } catch (_) {
      return null;
    }
  }

  void forceUpdate() {
    notifyListeners();
  }
}
