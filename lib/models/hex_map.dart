import 'package:collection/collection.dart';

import 'package:hex_grid_mapmaker/models/enums.dart';
import 'package:hex_grid_mapmaker/models/hex_region.dart';

/// A single hierarchical tier in the map.
///
/// - **Layer 0**: The geographic base layer. Regions contain concrete [HexTile]s.
/// - **Layer N (N>0)**: Abstract grouping layers. Regions contain references
///   (string IDs) to regions in Layer N-1 via [HexRegion.childRegions].
///
/// This hierarchy enables multi-resolution maps: e.g. Layer 0 = provinces,
/// Layer 1 = countries, Layer 2 = continents.
class HexLayer {
  /// The layer's position in the hierarchy (0 = base, higher = more abstract).
  int index;

  /// All regions that belong to this layer.
  List<HexRegion> regions;

  HexLayer({required this.index, List<HexRegion>? regions})
      : regions = regions ?? [];

  /// Safely looks up a region by ID. Returns null if not found (no exceptions).
  HexRegion? getRegion(String id) =>
      regions.firstWhereOrNull((r) => r.id == id);

  factory HexLayer.fromJson(Map<String, dynamic> json) {
    return HexLayer(
      index: json['index'] as int? ?? 0,
      regions: (json['regions'] as List<dynamic>?)
              ?.map((e) => HexRegion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'regions': regions.map((e) => e.toJson()).toList(),
      };
}

/// The root data structure containing the entire map: all layers, regions,
/// tiles, and metadata.
///
/// Serialized to/from JSON for file persistence. The [orientation] and
/// [version] fields are stored at the top level of the JSON file.
///
/// ## ID Uniqueness
///
/// Region IDs are globally unique across **all** layers. The [isIdInUse]
/// method enforces this invariant during ID assignment and renaming.
class HexMap {
  /// Schema version for forward compatibility with future format changes.
  String version;

  /// The hex grid layout orientation (pointy-topped or flat-topped).
  MapOrientation orientation;

  /// All layers in the map, sorted by [HexLayer.index] ascending.
  List<HexLayer> layers;

  HexMap({
    this.version = '1.0',
    this.orientation = MapOrientation.pointyTopped,
    List<HexLayer>? layers,
  }) : layers = layers ?? [];

  /// Safely looks up a layer by index. Returns null if not found.
  HexLayer? getLayer(int index) =>
      layers.firstWhereOrNull((l) => l.index == index);

  /// Returns true if any region across all layers uses this ID.
  ///
  /// Used by [MapState.updateRegionId] to prevent duplicate IDs which
  /// would break the parent-child reference system.
  bool isIdInUse(String id) =>
      layers.any((l) => l.regions.any((r) => r.id == id));

  /// Deserializes from a JSON map. Orientation is stored as a string
  /// (`'pointy-topped'` or `'flat-topped'`) for human readability.
  factory HexMap.fromJson(Map<String, dynamic> json) {
    return HexMap(
      version: json['version'] as String? ?? '1.0',
      orientation: json['orientation'] == 'flat-topped'
          ? MapOrientation.flatTopped
          : MapOrientation.pointyTopped,
      layers: (json['layers'] as List<dynamic>?)
              ?.map((e) => HexLayer.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'orientation': orientation == MapOrientation.pointyTopped
            ? 'pointy-topped'
            : 'flat-topped',
        'layers': layers.map((e) => e.toJson()).toList(),
      };
}
