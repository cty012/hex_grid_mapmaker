import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/enums.dart';
import 'package:hex_grid_mapmaker/models/hex_region.dart';
import 'package:hex_grid_mapmaker/models/hex_tile.dart';
import 'package:hex_grid_mapmaker/services/hex_geometry.dart' as geo;
import 'package:hex_grid_mapmaker/services/path_builder.dart' as paths;
import 'package:hex_grid_mapmaker/state/editor_state.dart';
import 'package:hex_grid_mapmaker/state/map_state.dart';
import 'package:hex_grid_mapmaker/utils/polylabel.dart';

/// Pure painting — all math delegated to services.
class HexPainter extends CustomPainter {
  final MapState mapState;
  final EditorState editorState;
  final double hexSize;
  final HexTile? hoverTile;
  final double scale;
  final Animation<double> pulseAnimation;

  HexPainter({
    required this.mapState,
    required this.editorState,
    required this.pulseAnimation,
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

    final labelDrawers = <VoidCallback>[];
    final highlightDrawers = <VoidCallback>[];

    for (int l = 0; l <= editorState.activeLayerIndex; l++) {
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

    // Grid
    if (editorState.showGrid) {
      final gridStroke = Paint()
        ..color = Colors.white30
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 / scale;
      for (int q = -20; q <= 20; q++) {
        for (int r = -20; r <= 20; r++) {
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

    // Hover
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
