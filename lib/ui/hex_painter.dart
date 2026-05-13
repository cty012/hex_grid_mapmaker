import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/enums.dart';
import 'package:hex_grid_mapmaker/models/hex_region.dart';
import 'package:hex_grid_mapmaker/models/hex_tile.dart';
import 'package:hex_grid_mapmaker/services/hex_geometry.dart' as geo;
import 'package:hex_grid_mapmaker/services/path_builder.dart' as paths;
import 'package:hex_grid_mapmaker/state/editor_state.dart';
import 'package:hex_grid_mapmaker/state/map_state.dart';
import 'package:hex_grid_mapmaker/utils/polylabel.dart';

/// Custom painter that renders the hex grid, region fills, boundaries,
/// selection highlights, labels, and hover feedback.
///
/// ## Rendering Pipeline
///
/// 1. **Region fills**: For each layer up to the active one, iterate regions.
///    If the region has cached boundary paths, clip-fill using those paths.
///    Otherwise, fall back to drawing individual hex tiles.
/// 2. **Grid overlay**: Draw an unfilled hex grid (41×41 tiles centered at origin).
/// 3. **Selection highlights**: Pulsating yellow stroke on the selected region.
/// 4. **Labels**: Text placed at the Pole of Inaccessibility (via Polylabel).
/// 5. **Hover**: White-highlighted hex under the mouse cursor.
///
/// Highlights and labels are drawn in deferred passes to ensure they render
/// on top of all region fills.
///
/// All coordinate math is delegated to [hex_geometry.dart] and
/// [path_builder.dart] — this class only calls `geo.*` and `paths.*`.
class HexPainter extends CustomPainter {
  final MapState mapState;       // Read-only access to map data.
  final EditorState editorState;  // Read-only access to UI state.
  final double hexSize;           // Pixel radius of each hex.
  final HexTile? hoverTile;       // Tile under the cursor (null if none).
  final double scale;             // Current zoom level (for stroke scaling).
  final Animation<double> pulseAnimation; // Drives selection glow opacity.
  final Matrix4 viewTransform;    // InteractiveViewer's current transform.
  final Size viewportSize;        // Screen viewport dimensions.

  HexPainter({
    required this.mapState,
    required this.editorState,
    required this.pulseAnimation,
    required this.viewTransform,
    required this.viewportSize,
    this.hexSize = 40.0,
    this.hoverTile,
    this.scale = 1.0,
  }) : super(repaint: pulseAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);

    final hexMap = mapState.hexMap;
    final orientation = hexMap.orientation;

    final selectedStrokePaint = Paint()
      ..color = Colors.yellowAccent.withValues(alpha: pulseAnimation.value)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 / scale;

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;

    // Deferred draw lists — ensures highlights and labels render on top.
    final labelDrawers = <VoidCallback>[];
    final highlightDrawers = <VoidCallback>[];

    // Render at most 2 layers: the previous layer (dimmed) and the active layer.
    final startLayer = (editorState.activeLayerIndex - 1).clamp(0, editorState.activeLayerIndex);
    for (int l = startLayer; l <= editorState.activeLayerIndex; l++) {
      final currentLayer = hexMap.getLayer(l);
      if (currentLayer == null) continue;
      final isActiveLayer = l == editorState.activeLayerIndex;

      for (final region in currentLayer.regions) {
        final regionTiles = mapState.getTilesForRegion(region, l);
        if (regionTiles.isEmpty) continue;

        Color regionColor = _resolveColor(region);
        if (!isActiveLayer) {
          regionColor = regionColor.withValues(alpha: regionColor.a * 0.5);
        }
        fillPaint.color = regionColor;

        final isSelected =
            isActiveLayer && region.id == editorState.activeRegionId;

        List<Path> bPaths = [];
        if (region.cachedBoundary != null &&
            region.cachedBoundary!.isNotEmpty) {
          bPaths = paths.buildBoundaryPaths(
              region.cachedBoundary!, orientation, hexSize);
        }

        final combinedPath = Path();
        for (final p in bPaths) {
          combinedPath.addPath(p, Offset.zero);
        }

        if (bPaths.isNotEmpty) {
          canvas.save();
          canvas.clipPath(combinedPath);
          canvas.drawPath(combinedPath, fillPaint);
          canvas.restore();

          if (isSelected) {
            highlightDrawers.add(() {
              canvas.save();
              canvas.clipPath(combinedPath);
              canvas.drawPath(
                  combinedPath,
                  Paint()
                    ..color = selectedStrokePaint.color
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = selectedStrokePaint.strokeWidth * 2);
              canvas.restore();
            });
          }
        } else {
          for (final tile in regionTiles) {
            _drawHex(canvas, orientation, null, fillPaint, tile);
            if (isSelected) {
              highlightDrawers.add(() {
                _drawHex(canvas, orientation, selectedStrokePaint, null, tile);
              });
            }
          }
        }

        if (isActiveLayer &&
            editorState.labelDisplay != LabelDisplay.none &&
            regionTiles.isNotEmpty) {
          _computeLabelIfNeeded(region, regionTiles, orientation);
          final center = region.cachedLabelPosition!;
          final label = editorState.labelDisplay == LabelDisplay.id
              ? region.id
              : region.name;

          labelDrawers.add(() {
            final tp = TextPainter(
              text: TextSpan(
                text: label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16 / scale,
                  fontWeight: FontWeight.bold,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
            );
            tp.layout();
            tp.paint(canvas,
                Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
          });
        }
      }
    }

    // Draw an "infinite" hex grid by computing which tiles are visible.
    // We invert the InteractiveViewer transform to find the pixel-space
    // bounding box of the viewport, then convert corners to hex coords.
    if (editorState.showGrid) {
      final gridStroke = Paint()
        ..color = Colors.white30
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 / scale;

      // Compute the visible rectangle in canvas space by inverting the
      // InteractiveViewer transform, then offset by the canvas center
      // (since paint() calls translate(w/2, h/2) before drawing).
      final screenRect = Offset.zero & viewportSize;
      final canvasRect = MatrixUtils.inverseTransformRect(viewTransform, screenRect);
      final cx = size.width / 2, cy = size.height / 2;
      final minPx = canvasRect.left - cx, maxPx = canvasRect.right - cx;
      final minPy = canvasRect.top - cy, maxPy = canvasRect.bottom - cy;

      // Convert all 4 pixel bbox corners to hex coordinates. Because hex
      // axes are non-orthogonal (skewed), a pixel-space rectangle maps to
      // a parallelogram in (q,r) space — so we must check all corners to
      // find the true min/max, not just top-left and bottom-right.
      final c0 = geo.pixelToHex(orientation, hexSize, Offset(minPx, minPy));
      final c1 = geo.pixelToHex(orientation, hexSize, Offset(maxPx, minPy));
      final c2 = geo.pixelToHex(orientation, hexSize, Offset(minPx, maxPy));
      final c3 = geo.pixelToHex(orientation, hexSize, Offset(maxPx, maxPy));
      final qMin = [c0.q, c1.q, c2.q, c3.q].reduce((a, b) => a < b ? a : b) - 2;
      final qMax = [c0.q, c1.q, c2.q, c3.q].reduce((a, b) => a > b ? a : b) + 2;
      final rMin = [c0.r, c1.r, c2.r, c3.r].reduce((a, b) => a < b ? a : b) - 2;
      final rMax = [c0.r, c1.r, c2.r, c3.r].reduce((a, b) => a > b ? a : b) + 2;

      for (int q = qMin; q <= qMax; q++) {
        for (int r = rMin; r <= rMax; r++) {
          _drawHex(canvas, orientation, gridStroke, null, HexTile(q: q, r: r));
        }
      }
    }

    for (final d in highlightDrawers) {
      d();
    }
    for (final d in labelDrawers) {
      d();
    }

    // Draw hover indicator for the tile under the cursor.
    if (hoverTile != null) {
      _drawHex(
          canvas,
          orientation,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0 / scale,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.3)
            ..style = PaintingStyle.fill,
          hoverTile!);
    }
  }

  /// Draws a single hexagon at [tile]'s pixel position.
  void _drawHex(Canvas canvas, MapOrientation orientation, Paint? stroke,
      Paint? fill, HexTile tile) {
    final center = geo.hexToPixel(orientation, hexSize, tile);
    final corners = geo.hexCorners(orientation, hexSize, center);
    final path = Path()..moveTo(corners[0].dx, corners[0].dy);
    for (int i = 1; i < 6; i++) {
      path.lineTo(corners[i].dx, corners[i].dy);
    }
    path.close();
    if (fill != null) canvas.drawPath(path, fill);
    if (stroke != null) canvas.drawPath(path, stroke);
  }

  /// Resolves a region's fill color from its attributes.
  ///
  /// If the region has a `'color'` attribute (hex string like `'#FF5733'`),
  /// it is parsed. Otherwise, a deterministic color is generated from the
  /// region name's hash code.
  Color _resolveColor(HexRegion region) {
    if (region.attributes.containsKey('color')) {
      var s = region.attributes['color'].toString();
      if (s.startsWith('#')) s = s.substring(1);
      if (s.length == 6) s = 'FF$s';
      return Color(int.tryParse(s, radix: 16) ?? 0xFF000000);
    }
    return Color((region.name.hashCode & 0xFFFFFF) | 0xFF000000)
        .withValues(alpha: 0.6);
  }

  /// Computes and caches the label position using Polylabel.
  ///
  /// Builds vertex polygons from the boundary edges, classifies rings as
  /// outer boundaries vs holes using signed area, then runs Polylabel on
  /// each component. If multiple components produce equal distances,
  /// the one closest to the geometric center of the region's tiles wins.
  void _computeLabelIfNeeded(
      HexRegion region, List<HexTile> tiles, MapOrientation orientation) {
    if (region.cachedLabelPosition != null) return;

    if (region.cachedBoundary != null && region.cachedBoundary!.isNotEmpty) {
      final allRings = paths.buildBoundaryPolygons(
          region.cachedBoundary!, orientation, hexSize);
      final ringData = allRings
          .map((r) => {'ring': r, 'area': paths.signedArea(r)})
          .toList()
        ..sort(
            (a, b) => (b['area'] as double).abs().compareTo(
                (a['area'] as double).abs()));

      if (ringData.isNotEmpty) {
        final maxSign = (ringData.first['area'] as double).sign;
        final outerRings = <List<Offset>>[];
        final holes = <List<Offset>>[];
        for (final r in ringData) {
          if ((r['area'] as double).sign == maxSign) {
            outerRings.add(r['ring'] as List<Offset>);
          } else {
            holes.add(r['ring'] as List<Offset>);
          }
        }

        final polygons = outerRings.map((o) => [o]).toList();
        for (final hole in holes) {
          for (final poly in polygons) {
            if (paths.pointInPolygon(hole.first, poly.first)) {
              poly.add(hole);
              break;
            }
          }
        }

        Offset? bestCenter;
        double maxDist = -1;
        for (final poly in polygons) {
          final result = polylabel(poly, precision: 0.5);
          if (result.distance > maxDist) {
            maxDist = result.distance;
            bestCenter = result.center;
          } else if (result.distance == maxDist) {
            double avgQ = 0, avgR = 0;
            for (final t in tiles) {
              avgQ += t.q;
              avgR += t.r;
            }
            avgQ /= tiles.length;
            avgR /= tiles.length;
            final actualCenter =
                geo.hexFracToPixel(orientation, hexSize, avgQ, avgR);
            if (bestCenter == null ||
                (result.center - actualCenter).distance <
                    (bestCenter - actualCenter).distance) {
              bestCenter = result.center;
            }
          }
        }
        region.cachedLabelPosition = bestCenter ?? Offset.zero;
      } else {
        region.cachedLabelPosition = Offset.zero;
      }
    } else if (region.tiles != null && region.tiles!.isNotEmpty) {
      region.cachedLabelPosition =
          geo.hexToPixel(orientation, hexSize, region.tiles!.first);
    } else {
      region.cachedLabelPosition = Offset.zero;
    }
  }

  @override
  bool shouldRepaint(covariant HexPainter oldDelegate) => true;
}
