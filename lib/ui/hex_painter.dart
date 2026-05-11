import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/hex_models.dart';
import 'package:hex_grid_mapmaker/state/app_state.dart';
import 'package:hex_grid_mapmaker/utils/polylabel.dart';

class HexPainter extends CustomPainter {
  final AppState state;
  final double hexSize;
  final HexTile? hoverTile;
  final double scale;
  final Animation<double> pulseAnimation;

  HexPainter({
    required this.state,
    required this.pulseAnimation,
    this.hexSize = 40.0,
    this.hoverTile,
    this.scale = 1.0,
  }) : super(repaint: pulseAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);

    final hexMap = state.hexMap;

    // Draw background grid
    if (state.showGrid) {
      final gridStroke = Paint()
        ..color = Colors.white10
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 / scale;

      // Draw a 40x40 grid around center
      for (int q = -20; q <= 20; q++) {
        for (int r = -20; r <= 20; r++) {
          _drawHex(canvas, hexMap, gridStroke, null, HexTile(q: q, r: r));
        }
      }
    }

    final selectedStrokePaint = Paint()
      ..color = Colors.yellowAccent.withValues(alpha: pulseAnimation.value)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0 / scale;

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;

    for (int l = 0; l <= state.activeLayerIndex; l++) {
      HexLayer? currentLayer;
      try {
        currentLayer = hexMap.layers.firstWhere((layer) => layer.index == l);
      } catch (_) {}

      if (currentLayer == null) continue;

      bool isActiveLayer = (l == state.activeLayerIndex);

      for (var region in currentLayer.regions) {
        List<HexTile> regionTiles = state.getTilesForRegion(region, l);
        if (regionTiles.isEmpty) continue;
        // Determine color
        Color regionColor;
        if (region.attributes.containsKey('color')) {
          String colorStr = region.attributes['color'].toString();
          if (colorStr.startsWith('#')) colorStr = colorStr.substring(1);
          if (colorStr.length == 6) colorStr = 'FF$colorStr';
          regionColor = Color(int.tryParse(colorStr, radix: 16) ?? 0xFF000000);
        } else {
          regionColor = Color(
            (region.name.hashCode & 0xFFFFFF) | 0xFF000000,
          ).withValues(alpha: 0.6);
        }

        if (!isActiveLayer) {
          // Make lower layers fainter
          regionColor = regionColor.withValues(alpha: regionColor.a * 0.5);
        }

        fillPaint.color = regionColor;
        final isSelected = isActiveLayer && region.id == state.activeRegionId;

        List<Path> bPaths = [];
        if (region.cachedBoundary != null &&
            region.cachedBoundary!.isNotEmpty) {
          bPaths = _buildBoundaryPaths(region.cachedBoundary!, hexMap);
        }

        Path combinedPath = Path();
        for (var p in bPaths) {
          combinedPath.addPath(p, Offset.zero);
        }

        if (bPaths.isNotEmpty) {
          canvas.save();
          canvas.clipPath(combinedPath);
          canvas.drawPath(combinedPath, fillPaint);

          if (isSelected) {
            final innerStroke = Paint()
              ..color = selectedStrokePaint.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = selectedStrokePaint.strokeWidth * 2;
            canvas.drawPath(combinedPath, innerStroke);
          }
          canvas.restore();
        } else {
          for (var tile in regionTiles) {
            Paint? currentStroke;
            if (isSelected) {
              currentStroke = selectedStrokePaint;
            } else {
              currentStroke = null;
            }

            _drawHex(canvas, hexMap, currentStroke, fillPaint, tile);
          }
        }

        if (isActiveLayer &&
            state.labelDisplay != 'None' &&
            regionTiles.isNotEmpty) {
          if (region.cachedLabelPosition == null) {
            if (region.cachedBoundary != null &&
                region.cachedBoundary!.isNotEmpty) {
              final allRings = _buildBoundaryPolygons(
                region.cachedBoundary!,
                hexMap,
              );

              List<Map<String, dynamic>> ringData = allRings
                  .map((r) => {'ring': r, 'area': _signedArea(r)})
                  .toList();
              ringData.sort(
                (a, b) => (b['area'] as double).abs().compareTo(
                  (a['area'] as double).abs(),
                ),
              );

              if (ringData.isNotEmpty) {
                double maxAreaSign = (ringData.first['area'] as double).sign;

                List<List<Offset>> outerRings = [];
                List<List<Offset>> holes = [];

                for (var r in ringData) {
                  if ((r['area'] as double).sign == maxAreaSign) {
                    outerRings.add(r['ring'] as List<Offset>);
                  } else {
                    holes.add(r['ring'] as List<Offset>);
                  }
                }

                List<List<List<Offset>>> polygons = outerRings
                    .map((o) => [o])
                    .toList();

                for (var hole in holes) {
                  for (var poly in polygons) {
                    if (_pointInPolygon(hole.first, poly.first)) {
                      poly.add(hole);
                      break;
                    }
                  }
                }

                Offset? bestCenter;
                double maxDist = -1;

                for (var poly in polygons) {
                  final result = polylabel(poly, precision: 0.5);
                  if (result.distance > maxDist) {
                    maxDist = result.distance;
                    bestCenter = result.center;
                  } else if (result.distance == maxDist) {
                    double avgQ = 0, avgR = 0;
                    for (var tile in regionTiles) {
                      avgQ += tile.q;
                      avgR += tile.r;
                    }
                    avgQ /= regionTiles.length;
                    avgR /= regionTiles.length;
                    Offset actualCenter = hexFracToPixel(hexMap, avgQ, avgR);
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
              // Fallback for layer 0 regions that somehow have no boundary cache
              region.cachedLabelPosition = hexToPixel(
                hexMap,
                region.tiles!.first,
              );
            } else {
              region.cachedLabelPosition = Offset.zero;
            }
          }

          final center = region.cachedLabelPosition!;
          final label = state.labelDisplay == 'ID' ? region.id : region.name;

          final textPainter = TextPainter(
            text: TextSpan(
              text: label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 36 / scale,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(blurRadius: 9, color: Colors.black)],
              ),
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
          );
          textPainter.layout();
          textPainter.paint(
            canvas,
            Offset(
              center.dx - textPainter.width / 2,
              center.dy - textPainter.height / 2,
            ),
          );
        }
      }
    }

    if (hoverTile != null) {
      final hoverFill = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      final hoverStroke = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0 / scale;
      _drawHex(canvas, hexMap, hoverStroke, hoverFill, hoverTile!);
    }
  }

  void _drawHex(
    Canvas canvas,
    HexMap hexMap,
    Paint? stroke,
    Paint? fill,
    HexTile tile,
  ) {
    final center = hexToPixel(hexMap, tile);
    final corners = _hexCorners(hexMap, center);

    final path = Path();
    path.moveTo(corners[0].dx, corners[0].dy);
    for (int i = 1; i < 6; i++) {
      path.lineTo(corners[i].dx, corners[i].dy);
    }
    path.close();

    if (fill != null) {
      canvas.drawPath(path, fill);
    }
    if (stroke != null) {
      canvas.drawPath(path, stroke);
    }
  }

  Offset hexToPixel(HexMap hexMap, HexTile hex) {
    return hexFracToPixel(hexMap, hex.q.toDouble(), hex.r.toDouble());
  }

  Offset hexFracToPixel(HexMap hexMap, double q, double r) {
    final isPointy = hexMap.orientation == 'pointy-topped';
    double x, y;
    if (isPointy) {
      x = hexSize * math.sqrt(3) * (q + r / 2);
      y = hexSize * 3 / 2 * r;
    } else {
      x = hexSize * 3 / 2 * q;
      y = hexSize * math.sqrt(3) * (r + q / 2);
    }
    return Offset(x, y);
  }

  List<Offset> _hexCorners(HexMap hexMap, Offset center) {
    final isPointy = hexMap.orientation == 'pointy-topped';
    final corners = <Offset>[];
    for (int i = 0; i < 6; i++) {
      final angleDeg = 60 * i - (isPointy ? 30 : 0);
      final angleRad = math.pi / 180 * angleDeg;
      corners.add(
        Offset(
          center.dx + hexSize * math.cos(angleRad),
          center.dy + hexSize * math.sin(angleRad),
        ),
      );
    }
    return corners;
  }

  @override
  bool shouldRepaint(covariant HexPainter oldDelegate) {
    // In a real app we'd compare state fields, for simplicity we repaint often
    return true;
  }

  List<Path> _buildBoundaryPaths(Set<DirectedEdge> boundary, HexMap hexMap) {
    Set<DirectedEdge> unvisited = Set.from(boundary);
    List<Path> paths = [];

    while (unvisited.isNotEmpty) {
      DirectedEdge start = unvisited.first;
      Path path = Path();

      DirectedEdge current = start;
      bool first = true;

      while (true) {
        unvisited.remove(current);

        final center = hexToPixel(hexMap, HexTile(q: current.q, r: current.r));
        final corners = _hexCorners(hexMap, center);

        if (first) {
          path.moveTo(corners[current.d].dx, corners[current.d].dy);
          first = false;
        }
        path.lineTo(
          corners[(current.d + 1) % 6].dx,
          corners[(current.d + 1) % 6].dy,
        );

        var opt1 = DirectedEdge(current.q, current.r, (current.d + 1) % 6);
        const dq = [1, 0, -1, -1, 0, 1];
        const dr = [0, 1, 1, 0, -1, -1];
        var nQ = current.q + dq[(current.d + 1) % 6];
        var nR = current.r + dr[(current.d + 1) % 6];
        var opt2 = DirectedEdge(nQ, nR, (current.d + 5) % 6);

        if (unvisited.contains(opt1)) {
          current = opt1;
        } else if (unvisited.contains(opt2)) {
          current = opt2;
        } else {
          path.close();
          break;
        }
      }
      paths.add(path);
    }
    return paths;
  }

  List<List<Offset>> _buildBoundaryPolygons(
    Set<DirectedEdge> boundary,
    HexMap hexMap,
  ) {
    Set<DirectedEdge> unvisited = Set.from(boundary);
    List<List<Offset>> polygons = [];

    while (unvisited.isNotEmpty) {
      DirectedEdge start = unvisited.first;
      List<Offset> polygon = [];

      DirectedEdge current = start;
      bool first = true;

      while (true) {
        unvisited.remove(current);

        final center = hexToPixel(hexMap, HexTile(q: current.q, r: current.r));
        final corners = _hexCorners(hexMap, center);

        if (first) {
          polygon.add(corners[current.d]);
          first = false;
        }
        polygon.add(corners[(current.d + 1) % 6]);

        var opt1 = DirectedEdge(current.q, current.r, (current.d + 1) % 6);
        const dq = [1, 0, -1, -1, 0, 1];
        const dr = [0, 1, 1, 0, -1, -1];
        var nQ = current.q + dq[(current.d + 1) % 6];
        var nR = current.r + dr[(current.d + 1) % 6];
        var opt2 = DirectedEdge(nQ, nR, (current.d + 5) % 6);

        if (unvisited.contains(opt1)) {
          current = opt1;
        } else if (unvisited.contains(opt2)) {
          current = opt2;
        } else {
          break;
        }
      }
      polygons.add(polygon);
    }
    return polygons;
  }

  double _signedArea(List<Offset> ring) {
    double area = 0;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      area += (ring[j].dx * ring[i].dy) - (ring[i].dx * ring[j].dy);
    }
    return area / 2;
  }

  bool _pointInPolygon(Offset p, List<Offset> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if ((polygon[i].dy > p.dy) != (polygon[j].dy > p.dy) &&
          (p.dx <
              (polygon[j].dx - polygon[i].dx) *
                      (p.dy - polygon[i].dy) /
                      (polygon[j].dy - polygon[i].dy) +
                  polygon[i].dx)) {
        inside = !inside;
      }
    }
    return inside;
  }
}
