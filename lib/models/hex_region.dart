import 'package:flutter/material.dart';

import 'package:hex_grid_mapmaker/models/hex_tile.dart';

/// A named, bounded area on the map containing tiles or child region references.
///
/// ## Layer-Dependent Structure
///
/// - **Layer 0 regions** store a concrete [tiles] list — each tile is a
///   discrete hex coordinate that the region occupies.
/// - **Layer N (N>0) regions** store a [childRegions] list of IDs pointing
///   to regions in Layer N-1. Their geographic footprint is the union of
///   all descendant tiles, computed recursively.
///
/// ## Rendering Cache
///
/// [cachedBoundary] and [cachedLabelPosition] are transient, in-memory-only
/// caches populated by [boundary_service.dart] and the Polylabel algorithm.
/// They are **not** serialized to JSON — they are recomputed on load via
/// [MapState.loadMap].
///
/// ## Attributes
///
/// The [attributes] map stores arbitrary user-defined key-value metadata.
/// The special key `'color'` is recognized by [HexPainter] to set the
/// region's fill color (hex string like `'#FF5733'` or `'FF5733'`).
///
/// Three convenience methods ([setAttribute], [removeAttribute],
/// [renameAttribute]) are provided to make attribute manipulation
/// readable at call sites, while keeping the map publicly accessible
/// for direct iteration in the properties panel.
class HexRegion {
  /// Unique identifier across all layers. Validated globally by [HexMap.isIdInUse].
  String id;

  /// Human-readable display name shown in the hierarchy panel and labels.
  String name;

  /// Arbitrary user-defined metadata (e.g. `{'color': '#FF5733', 'population': '1200'}`).
  Map<String, dynamic> attributes;

  /// Concrete hex tiles owned by this region (Layer 0 only; null for higher layers).
  List<HexTile>? tiles;

  /// IDs of child regions in the layer below (Layer N>0 only; null for Layer 0).
  List<String>? childRegions;

  /// Pre-computed external boundary edges. Invalidated on any tile/child change.
  Set<DirectedEdge>? cachedBoundary;

  /// Optimal label placement point (Pole of Inaccessibility via Polylabel).
  Offset? cachedLabelPosition;

  HexRegion({
    required this.id,
    required this.name,
    Map<String, dynamic>? attributes,
    this.tiles,
    this.childRegions,
  }) : attributes = attributes ?? {};

  /// Sets or updates a single attribute key-value pair.
  void setAttribute(String key, dynamic value) => attributes[key] = value;

  /// Removes an attribute by key. Returns the removed value, or null.
  dynamic removeAttribute(String key) => attributes.remove(key);

  /// Renames an attribute key while preserving its value.
  ///
  /// Removes [oldKey] from the map and re-inserts the value under [newKey].
  /// If [oldKey] doesn't exist, [newKey] is inserted with a null value.
  void renameAttribute(String oldKey, String newKey) {
    final val = attributes.remove(oldKey);
    attributes[newKey] = val;
  }

  /// Deserializes from a JSON map (e.g. loaded from a `.json` map file).
  ///
  /// Creates a **mutable copy** of the attributes map via `Map.from()` to
  /// prevent the "unmodifiable map" bug where the JSON decoder's internal
  /// map is reused directly.
  factory HexRegion.fromJson(Map<String, dynamic> json) {
    return HexRegion(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      attributes: Map<String, dynamic>.from(
        json['attributes'] as Map<String, dynamic>? ?? {},
      ),
      tiles: (json['tiles'] as List<dynamic>?)
          ?.map((e) => HexTile.fromJson(e as Map<String, dynamic>))
          .toList(),
      childRegions: (json['childRegions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  /// Serializes to a JSON map for persistence.
  ///
  /// Creates a **defensive copy** of the attributes map to prevent external
  /// code from mutating the region's live state through the returned map.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'name': name,
      'attributes': Map<String, dynamic>.from(attributes),
    };
    if (tiles != null) map['tiles'] = tiles!.map((e) => e.toJson()).toList();
    if (childRegions != null) map['childRegions'] = childRegions;
    return map;
  }
}
