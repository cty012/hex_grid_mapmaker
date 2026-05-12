import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/hex_models.dart';



/// The central state controller for the Hex Grid Mapmaker application.
/// 
/// This class acts as the single source of truth for the [HexMap] data structure
/// and manages all interactions, tools, UI state, and rendering caches.
/// Crucially, it handles the mathematical boundary propagation logic to keep
/// all hierarchical map layers in sync geometrically.
class AppState extends ChangeNotifier {
  /// The global map data containing all layers, regions, and tiles.
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
    int targetIndex = activeLayerIndex;
    HexLayer targetLayer = hexMap.layers.firstWhere((l) => l.index == targetIndex);

    if (targetIndex == 0) {
      if (hexMap.layers.length == 1) {
        // Only layer 0 exists, just clear its regions
        targetLayer.regions.clear();
      } else {
        // Convert layer 1 regions to hex tiles
        HexLayer layer1 = hexMap.layers.firstWhere((l) => l.index == 1);
        for (var region in layer1.regions) {
          Set<HexTile> allTiles = {};
          if (region.childRegions != null) {
            for (var childId in region.childRegions!) {
              try {
                var childRegion = targetLayer.regions.firstWhere((r) => r.id == childId);
                if (childRegion.tiles != null) {
                  allTiles.addAll(childRegion.tiles!);
                }
              } catch (_) {}
            }
          }
          region.tiles = allTiles.toList();
          region.childRegions = null;
        }
        hexMap.layers.remove(targetLayer);
      }
    } else {
      // Deleting a layer > 0
      try {
        HexLayer parentLayer = hexMap.layers.firstWhere((l) => l.index == targetIndex + 1);
        for (var region in parentLayer.regions) {
          Set<String> newChildRegions = {};
          if (region.childRegions != null) {
            for (var childId in region.childRegions!) {
              try {
                var childRegion = targetLayer.regions.firstWhere((r) => r.id == childId);
                if (childRegion.childRegions != null) {
                  newChildRegions.addAll(childRegion.childRegions!);
                }
              } catch (_) {}
            }
          }
          region.childRegions = newChildRegions.toList();
        }
      } catch (_) {} // No parent layer, that's fine
      
      hexMap.layers.remove(targetLayer);
    }

    // Shift indices down
    if (!(targetIndex == 0 && hexMap.layers.length == 1 && hexMap.layers[0].index == 0)) {
      for (var layer in hexMap.layers) {
        if (layer.index > targetIndex) {
          layer.index--;
        }
      }
    }

    int newActiveLayer = activeLayerIndex;
    if (newActiveLayer >= hexMap.layers.length) {
      newActiveLayer = hexMap.layers.length - 1;
    }
    if (newActiveLayer < 0) newActiveLayer = 0;
    
    activeLayerIndex = newActiveLayer;
    activeRegionId = null;
    
    _recomputeAllBoundaries();
    notifyListeners();
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

  /// Computes the union of two boundaries using mathematical edge cancellation.
  /// 
  /// When adding a shape (like a tile or a sub-region) to an existing region,
  /// this algorithm dissolves internal walls. If a new edge opposes an existing
  /// edge, they represent an internal wall and both are removed. Otherwise,
  /// the new edge becomes part of the exterior perimeter.
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

  /// Computes the difference of two boundaries to create holes or dents.
  /// 
  /// When removing a shape from an existing region, the edges that formed
  /// the exterior of the removed shape must be stripped from the parent's boundary.
  /// Conversely, any *internal* edges of the removed shape now become exposed
  /// walls, forming a 'dent' or a 'hole' in the parent region.
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

  /// Recursively propagates newly added boundaries upwards through the map layers.
  /// 
  /// Whenever a tile is added to Layer 0, the boundary of its parent region on Layer 1
  /// must be expanded. Consequently, Layer 1's parent region on Layer 2 must also be
  /// expanded. This recursion ensures that high-level abstract boundaries remain perfectly
  /// synchronized with ground-level tile adjustments in O(1) mathematical time per layer.
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

  /// Recursively propagates removed boundaries upwards through the map layers.
  /// 
  /// Similar to [_propagateBoundaryAddition], when a tile is erased from Layer 0,
  /// this method propagates the subtraction (dents or holes) upwards so that Layer N
  /// perfectly reflects the geographical loss of the erased tiles.
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

  /// Resolves the specific region occupying a given hex tile on a specific layer.
  /// Because layers above 0 only store child region IDs, this recursively searches
  /// downward through the hierarchy to determine geometric overlap.
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

  /// Recursively flattens the hierarchy to retrieve all ground-level [HexTile]s
  /// that logically belong to the given abstract [region].
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

  String _getNextAvailableRegionId() {
    Set<int> usedIntIds = {};
    for (var layer in hexMap.layers) {
      for (var region in layer.regions) {
        int? intId = int.tryParse(region.id);
        if (intId != null && intId > 0) {
          usedIntIds.add(intId);
        }
      }
    }
    int nextId = 1;
    while (usedIntIds.contains(nextId)) {
      nextId++;
    }
    return nextId.toString();
  }

  void addRegion(String name) {
    final newId = _getNextAvailableRegionId();
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

  /// Safely renames a region's ID globally across the entire map hierarchy.
  /// 
  /// 1. Validates that the [newId] is globally unique across all layers.
  /// 2. Updates the `activeRegionId` state if the renamed region was currently selected.
  /// 3. Scans the parent layer (`activeLayerIndex + 1`) and automatically refactors any
  ///    `childRegions` arrays to use the [newId], preventing orphaned references.
  String? updateRegionId(HexRegion region, String newId) {
    if (newId.trim().isEmpty) return 'ID cannot be empty';
    if (region.id == newId) return null;

    for (var layer in hexMap.layers) {
      for (var r in layer.regions) {
        if (r.id == newId) {
          return 'ID already in use';
        }
      }
    }

    String oldId = region.id;
    region.id = newId;

    if (activeRegionId == oldId) {
      activeRegionId = newId;
    }

    try {
      final parentLayer = hexMap.layers.firstWhere((l) => l.index == activeLayerIndex + 1);
      for (var parentRegion in parentLayer.regions) {
        if (parentRegion.childRegions?.contains(oldId) ?? false) {
          int index = parentRegion.childRegions!.indexOf(oldId);
          parentRegion.childRegions![index] = newId;
        }
      }
    } catch (_) {}

    notifyListeners();
    return null;
  }

  /// Irreversibly deletes a region from the map.
  /// 
  /// This not only removes the region from its current layer but also strips its
  /// geometry from any parent regions on `layerIndex + 1` (creating a geographic hole)
  /// and removes its ID from any parent references. Child regions in lower layers are
  /// left orphaned but preserved.
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
