/// A single discrete coordinate on the hexagonal grid (cube coordinate system).
class HexTile {
  final int q;
  final int r;
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
/// Two adjacent hexes share opposite edges — cancelling them dissolves internal walls.
class DirectedEdge {
  final int q;
  final int r;
  final int d;

  const DirectedEdge(this.q, this.r, this.d);

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
