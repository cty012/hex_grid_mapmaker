import 'package:flutter/material.dart';

/// Represents the entire hex grid map, serving as the root data structure.
/// Contains configuration metadata and a hierarchical list of layers.
class HexMap {
  /// The schema version of the map JSON.
  String version;

  /// The visual orientation of the hexes: 'pointy-topped' or 'flat-topped'.
  String orientation;
  
  /// The hierarchical layers that make up the map structure.
  /// Layer 0 contains raw tiles, while Layer N>0 contains abstract regions.
  List<HexLayer> layers;

  HexMap({
    this.version = '1.0',
    this.orientation = 'pointy-topped',
    List<HexLayer>? layers,
  }) : layers = layers ?? [];

  factory HexMap.fromJson(Map<String, dynamic> json) {
    return HexMap(
      version: json['version'] as String? ?? '1.0',
      orientation: json['orientation'] as String? ?? 'pointy-topped',
      layers:
          (json['layers'] as List<dynamic>?)
              ?.map((e) => HexLayer.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'orientation': orientation,
      'layers': layers.map((e) => e.toJson()).toList(),
    };
  }
}

/// Represents a single hierarchical tier within the map.
/// Layer 0 acts as the foundational geographic layer made of literal hex tiles.
/// Higher layers (1, 2, 3...) represent logical groupings (e.g., countries, continents)
/// by referencing the IDs of child regions in the layer immediately below them.
class HexLayer {
  /// The hierarchical index of this layer (0 = base, 1+ = abstract).
  int index;

  /// The collection of distinct regions that exist on this layer.
  List<HexRegion> regions;

  HexLayer({required this.index, List<HexRegion>? regions})
    : regions = regions ?? [];

  factory HexLayer.fromJson(Map<String, dynamic> json) {
    return HexLayer(
      index: json['index'] as int? ?? 0,
      regions:
          (json['regions'] as List<dynamic>?)
              ?.map((e) => HexRegion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {'index': index, 'regions': regions.map((e) => e.toJson()).toList()};
  }
}

/// Defines a specific bounded area on the map.
/// A region can be either geographic (composed of [HexTile]s on Layer 0)
/// or abstract (composed of [childRegions] on Layer N).
class HexRegion {
  /// A globally unique identifier for this region.
  String id;

  /// The human-readable name of the region.
  String name;

  /// Dynamic key-value pairs for attaching custom metadata (e.g., population, biome).
  Map<String, dynamic> attributes;

  /// The geographic hex tiles that physically make up this region.
  /// This is ONLY populated if the region exists on Layer 0.
  List<HexTile>? tiles;

  /// The string IDs of the sub-regions that make up this region.
  /// This is ONLY populated if the region exists on Layer N (where N > 0).
  List<String>? childRegions;

  /// A transient, in-memory cache of the region's outer perimeter.
  /// Stored as an unordered set of directed edges. This prevents expensive
  /// O(N) boundary recalculations on every render frame.
  Set<DirectedEdge>? cachedBoundary;

  /// A transient, in-memory cache of the visual center of the region,
  /// calculated via the Polylabel algorithm (Pole of Inaccessibility).
  Offset? cachedLabelPosition;

  HexRegion({
    required this.id,
    required this.name,
    Map<String, dynamic>? attributes,
    this.tiles,
    this.childRegions,
    this.cachedLabelPosition,
  }) : attributes = attributes ?? {};

  factory HexRegion.fromJson(Map<String, dynamic> json) {
    return HexRegion(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      attributes: Map<String, dynamic>.from(json['attributes'] as Map<String, dynamic>? ?? {}),
      tiles: (json['tiles'] as List<dynamic>?)
          ?.map((e) => HexTile.fromJson(e as Map<String, dynamic>))
          .toList(),
      childRegions: (json['childRegions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'name': name,
      'attributes': Map<String, dynamic>.from(attributes),
    };
    if (tiles != null) {
      map['tiles'] = tiles!.map((e) => e.toJson()).toList();
    }
    if (childRegions != null) {
      map['childRegions'] = childRegions;
    }
    return map;
  }
}

/// Represents a single, discrete coordinate on the hexagonal grid
/// using the cube coordinate system.
class HexTile {
  /// The 'q' (column) axial coordinate.
  int q;

  /// The 'r' (row) axial coordinate.
  int r;

  /// The implicit 's' coordinate, derived mathematically since q + r + s = 0.
  int get s => -q - r;

  HexTile({required this.q, required this.r});

  factory HexTile.fromJson(Map<String, dynamic> json) {
    return HexTile(q: json['q'] as int? ?? 0, r: json['r'] as int? ?? 0);
  }

  Map<String, dynamic> toJson() {
    return {'q': q, 'r': r};
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HexTile &&
          runtimeType == other.runtimeType &&
          q == other.q &&
          r == other.r;

  @override
  int get hashCode => q.hashCode ^ r.hashCode;
}

/// Represents a singular line segment along the outer perimeter of a hex tile.
/// It is defined by the tile it belongs to and the direction `d` (0 to 5) it faces.
/// 
/// This class is the mathematical foundation for boundary calculation. By adding
/// an edge to a set, and removing its exact [opposite] edge if it already exists,
/// internal walls mathematically dissolve to leave only the external perimeter.
class DirectedEdge {
  /// The 'q' axial coordinate of the parent hex tile.
  final int q;

  /// The 'r' axial coordinate of the parent hex tile.
  final int r;

  /// The direction the edge faces on the hexagon, from 0 to 5.
  final int d;

  DirectedEdge(this.q, this.r, this.d);

  /// Calculates the exact opposing edge that would belong to an adjacent neighbor.
  /// If two hexes share a wall, one hex's edge and the neighbor's opposite edge
  /// perfectly overlap in space.
  DirectedEdge get opposite {
    // Relative coordinate offsets to find the adjacent hex in direction 'd'.
    const dq = [1, 0, -1, -1, 0, 1];
    const dr = [0, 1, 1, 0, -1, -1];
    // The opposite edge is on the neighbor hex, facing the opposite direction ((d + 3) % 6).
    return DirectedEdge(q + dq[d], r + dr[d], (d + 3) % 6);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectedEdge &&
          runtimeType == other.runtimeType &&
          q == other.q &&
          r == other.r &&
          d == other.d;

  @override
  int get hashCode => q.hashCode ^ r.hashCode ^ d.hashCode;
}
