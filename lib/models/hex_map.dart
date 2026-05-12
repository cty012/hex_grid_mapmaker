import 'package:collection/collection.dart';

import 'package:hex_grid_mapmaker/models/enums.dart';
import 'package:hex_grid_mapmaker/models/hex_region.dart';

/// A single hierarchical tier. Layer 0 = geographic tiles, Layer N = abstract groupings.
class HexLayer {
  int index;
  List<HexRegion> regions;

  HexLayer({required this.index, List<HexRegion>? regions})
      : regions = regions ?? [];

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

/// The root data structure containing all layers.
class HexMap {
  String version;
  MapOrientation orientation;
  List<HexLayer> layers;

  HexMap({
    this.version = '1.0',
    this.orientation = MapOrientation.pointyTopped,
    List<HexLayer>? layers,
  }) : layers = layers ?? [];

  HexLayer? getLayer(int index) =>
      layers.firstWhereOrNull((l) => l.index == index);

  /// Returns true if any region across all layers uses this ID.
  bool isIdInUse(String id) =>
      layers.any((l) => l.regions.any((r) => r.id == id));

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
