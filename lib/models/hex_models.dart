import 'package:flutter/material.dart';

class HexMap {
  String version;
  String orientation; // 'pointy-topped' or 'flat-topped'
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

class HexLayer {
  int index;
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
    this.cachedLabelPosition,
  }) : attributes = attributes ?? {};

  factory HexRegion.fromJson(Map<String, dynamic> json) {
    return HexRegion(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      attributes: json['attributes'] as Map<String, dynamic>? ?? {},
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
      'attributes': attributes,
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

class HexTile {
  int q;
  int r;

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

class DirectedEdge {
  final int q;
  final int r;
  final int d;

  DirectedEdge(this.q, this.r, this.d);

  DirectedEdge get opposite {
    const dq = [1, 0, -1, -1, 0, 1];
    const dr = [0, 1, 1, 0, -1, -1];
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
