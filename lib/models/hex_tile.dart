/// Pure value types for the hexagonal coordinate system.
///
/// These classes have no Flutter dependency and represent the fundamental
/// geometric primitives of the hex grid.
///
/// ## Coordinate System
///
/// This application uses **axial coordinates** (q, r), a projection of the
/// cube coordinate system (q, r, s) where `s = -q - r`. This gives O(1)
/// neighbor lookup and distance calculation without storing a redundant axis.
///
/// ## Boundary Representation
///
/// Region boundaries are stored as `Set<DirectedEdge>`. Each hex tile
/// contributes 6 directed edges (one per side, directions 0–5). When two
/// adjacent tiles belong to the same region, their shared internal wall
/// consists of a pair of opposite directed edges — adding one to a set that
/// already contains its opposite cancels both out, leaving only the external
/// perimeter. This gives O(1) boundary updates per tile add/remove.
library;

/// A single discrete coordinate on the hexagonal grid (axial/cube system).
///
/// Equality is defined by (q, r), making tiles usable as `Set`/`Map` keys
/// for O(1) membership tests during tile operations.
class HexTile {
  /// The column coordinate (horizontal axis in pointy-topped orientation).
  final int q;

  /// The row coordinate (diagonal axis).
  final int r;

  /// The implicit third cube axis, derived as `-q - r`.
  int get s => -q - r;

  const HexTile({required this.q, required this.r});

  factory HexTile.fromJson(Map<String, dynamic> json) =>
      HexTile(q: json['q'] as int? ?? 0, r: json['r'] as int? ?? 0);

  Map<String, dynamic> toJson() => {'q': q, 'r': r};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HexTile && q == other.q && r == other.r;

  @override
  int get hashCode => q.hashCode ^ r.hashCode;
}

/// A directed edge segment on a hex tile's perimeter, facing direction [d] (0–5).
///
/// Direction indices follow the hex geometry convention:
/// ```
///   d=0 → edge facing +q neighbor
///   d=1 → edge facing +r neighbor
///   d=2 → edge facing -q+r neighbor
///   d=3 → edge facing -q neighbor (opposite of d=0)
///   d=4 → edge facing -r neighbor (opposite of d=1)
///   d=5 → edge facing +q-r neighbor (opposite of d=2)
/// ```
///
/// The [opposite] getter returns the corresponding edge on the neighboring
/// tile. When two adjacent hexes share a wall, one's edge at direction `d`
/// is the other's edge at direction `(d+3) % 6` — this is the basis for the
/// O(1) boundary cancellation algorithm in [boundary_service.dart].
class DirectedEdge {
  /// The q-coordinate of the hex tile this edge belongs to.
  final int q;

  /// The r-coordinate of the hex tile this edge belongs to.
  final int r;

  /// The direction index (0–5) of this edge on the tile's perimeter.
  final int d;

  const DirectedEdge(this.q, this.r, this.d);

  /// Returns the matching edge on the adjacent tile that shares this wall.
  ///
  /// Uses precomputed neighbor offset tables (dq, dr) to find the adjacent
  /// tile, then flips the direction by 180° via `(d + 3) % 6`.
  DirectedEdge get opposite {
    const dq = [1, 0, -1, -1, 0, 1];
    const dr = [0, 1, 1, 0, -1, -1];
    return DirectedEdge(q + dq[d], r + dr[d], (d + 3) % 6);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectedEdge && q == other.q && r == other.r && d == other.d;

  @override
  int get hashCode => q.hashCode ^ r.hashCode ^ d.hashCode;
}
