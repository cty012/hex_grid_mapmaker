import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/hex_models.dart';
import 'package:hex_grid_mapmaker/state/app_state.dart';
import 'package:hex_grid_mapmaker/ui/hex_painter.dart';
import 'package:hex_grid_mapmaker/ui/inspector_panel.dart';
import 'package:hex_grid_mapmaker/ui/tool_palette.dart';
import 'package:provider/provider.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with SingleTickerProviderStateMixin {
  final double hexSize = 40.0;
  final TransformationController _transformationController =
      TransformationController();

  HexTile? hoverTile;

  double _currentScale = 1.0;
  
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _onTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (scale != _currentScale) {
      setState(() {
        _currentScale = scale;
      });
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleOrientation(AppState state) {
    state.setOrientation(
      state.hexMap.orientation == 'pointy-topped'
          ? 'flat-topped'
          : 'pointy-topped',
    );
  }

  Future<void> _loadMap(AppState state) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      try {
        final json = jsonDecode(content);
        final map = HexMap.fromJson(json);
        state.loadMap(map);
        _centerAndScaleMap(map);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Map loaded successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error loading map: $e')));
        }
      }
    }
  }

  void _centerAndScaleMap(HexMap map) {
    if (map.layers.isEmpty || map.layers[0].regions.isEmpty) return;

    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    bool hasTiles = false;

    for (var region in map.layers[0].regions) {
      if (region.tiles != null) {
        for (var tile in region.tiles!) {
          hasTiles = true;
          final isPointy = map.orientation == 'pointy-topped';
          double x, y;
          if (isPointy) {
            x = hexSize * math.sqrt(3) * (tile.q + tile.r / 2);
            y = hexSize * 3 / 2 * tile.r;
          } else {
            x = hexSize * 3 / 2 * tile.q;
            y = hexSize * math.sqrt(3) * (tile.r + tile.q / 2);
          }

          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (!hasTiles) return;

    minX -= hexSize * 2;
    maxX += hexSize * 2;
    minY -= hexSize * 2;
    maxY += hexSize * 2;

    double mapWidth = maxX - minX;
    double mapHeight = maxY - minY;

    if (mapWidth == 0 || mapHeight == 0) return;

    final viewportWidth = MediaQuery.of(context).size.width - 300;
    final viewportHeight = MediaQuery.of(context).size.height - kToolbarHeight;

    double scaleX = viewportWidth / mapWidth;
    double scaleY = viewportHeight / mapHeight;
    double scale = math.min(scaleX, scaleY).clamp(0.1, 2.0);

    double centerX = (minX + maxX) / 2;
    double centerY = (minY + maxY) / 2;

    double childCenterX = 5000 + centerX;
    double childCenterY = 5000 + centerY;

    double targetX = (viewportWidth / 2) - (childCenterX * scale);
    double targetY = (viewportHeight / 2) - (childCenterY * scale);

    _currentScale = scale;
    _transformationController.value = Matrix4.diagonal3Values(scale, scale, 1.0)
      ..setTranslationRaw(targetX, targetY, 0.0);
  }

  Future<void> _saveMap(AppState state) async {
    final result = await FilePicker.saveFile(
      dialogTitle: 'Save map',
      fileName: 'map.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null) {
      final file = File(result);
      final content = jsonEncode(state.hexMap.toJson());
      await file.writeAsString(content);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Map saved successfully')));
      }
    }
  }

  HexTile _pixelToHex(Offset localPosition, Size canvasSize, AppState state) {
    double x = localPosition.dx - canvasSize.width / 2;
    double y = localPosition.dy - canvasSize.height / 2;

    final isPointy = state.hexMap.orientation == 'pointy-topped';
    double q, r;

    if (isPointy) {
      q = (math.sqrt(3) / 3 * x - 1 / 3 * y) / hexSize;
      r = (2 / 3 * y) / hexSize;
    } else {
      q = (2 / 3 * x) / hexSize;
      r = (-1 / 3 * x + math.sqrt(3) / 3 * y) / hexSize;
    }

    return _hexRound(q, r);
  }

  HexTile _hexRound(double fracQ, double fracR) {
    double fracS = -fracQ - fracR;
    int qRound = fracQ.round();
    int rRound = fracR.round();
    int sRound = fracS.round();

    double qDiff = (qRound - fracQ).abs();
    double rDiff = (rRound - fracR).abs();
    double sDiff = (sRound - fracS).abs();

    if (qDiff > rDiff && qDiff > sDiff) {
      qRound = -rRound - sRound;
    } else if (rDiff > sDiff) {
      rRound = -qRound - sRound;
    } else {
      sRound = -qRound - rRound;
    }

    return HexTile(q: qRound, r: rRound);
  }

  void _onHover(Offset localPosition, Size canvasSize, AppState state) {
    final tile = _pixelToHex(localPosition, canvasSize, state);
    if (hoverTile != tile) {
      setState(() {
        hoverTile = tile;
      });
      // Optionally handle drag-drawing
    }
  }

  void _onTap(Offset localPosition, Size canvasSize, AppState state) {
    final tile = _pixelToHex(localPosition, canvasSize, state);

    if (state.activeTool == 'select') {
      final region = state.getRegionAtTile(tile);
      if (region != null) {
        state.setActiveRegion(region.id);
      } else {
        state.setActiveRegion(null);
      }
    } else if (state.activeTool == 'draw') {
      if (state.activeRegionId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a region in the Inspector first.'),
          ),
        );
        return;
      }
      state.addTileToActiveRegion(tile);
    } else if (state.activeTool == 'erase') {
      state.removeTile(tile);
    }
  }

  @override
  Widget build(BuildContext context) {
    const canvasSize = Size(10000, 10000);
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Hex Grid Mapmaker',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          Row(
            children: [
              const Text('Grid:'),
              Switch(
                value: state.showGrid,
                onChanged: (val) => state.setShowGrid(val),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Row(
            children: [
              const Text('Labels:'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: state.labelDisplay,
                items: ['None', 'ID', 'Name'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) state.setLabelDisplay(val);
                },
              ),
            ],
          ),
          const SizedBox(width: 24),
          IconButton(
            icon: const Icon(Icons.screen_rotation),
            tooltip: 'Toggle Orientation',
            onPressed: () => _toggleOrientation(state),
          ),
          IconButton(
            icon: const Icon(Icons.file_open),
            tooltip: 'Load JSON',
            onPressed: () => _loadMap(state),
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save JSON',
            onPressed: () => _saveMap(state),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                InteractiveViewer(
                  transformationController: _transformationController,
                  constrained: false,
                  minScale: 0.1,
                  maxScale: 5.0,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: MouseRegion(
                    onHover: (event) =>
                        _onHover(event.localPosition, canvasSize, state),
                    onExit: (_) => setState(() => hoverTile = null),
                    child: GestureDetector(
                      onTapUp: (details) =>
                          _onTap(details.localPosition, canvasSize, state),
                      child: CustomPaint(
                        size: canvasSize,
                        painter: HexPainter(
                          state: state,
                          hexSize: hexSize,
                          hoverTile: hoverTile,
                          scale: _currentScale,
                          pulseAnimation: _pulseAnimation,
                        ),
                      ),
                    ),
                  ),
                ),
                const ToolPalette(),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          const InspectorPanel(),
        ],
      ),
    );
  }
}
