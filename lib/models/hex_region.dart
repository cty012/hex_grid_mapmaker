import 'package:flutter/material.dart';

import 'package:hex_grid_mapmaker/models/hex_tile.dart';

/// A bounded area on the map with metadata and cached rendering state.
class HexRegion {
  String id;
  String name;
  Map<String, dynamic> attributes;
  List<HexTile>? tiles;
  List<String>? childRegions;
  Set<DirectedEdge>? cachedBoundary;
  Offset? cachedLabelPosition;

  HexRegion({
    required this.id,
    required this.name,
    Map<String, dynamic>? attributes,
    this.tiles,
    this.childRegions,
  }) : attributes = attributes ?? {};

  // Convenience methods for safe attribute manipulation.
  void setAttribute(String key, dynamic value) => attributes[key] = value;
  dynamic removeAttribute(String key) => attributes.remove(key);
  void renameAttribute(String oldKey, String newKey) {
    final val = attributes.remove(oldKey);
    attributes[newKey] = val;
  }

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
