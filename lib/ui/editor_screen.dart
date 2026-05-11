import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/hex_models.dart';
import 'package:hex_grid_mapmaker/state/app_state.dart';
import 'package:hex_grid_mapmaker/ui/hex_painter.dart';
import 'package:hex_grid_mapmaker/ui/hierarchy_panel.dart';
import 'package:hex_grid_mapmaker/ui/properties_panel.dart';
import 'package:hex_grid_mapmaker/ui/tool_palette.dart';
import 'package:provider/provider.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with SingleTickerProviderStateMixin {
  final double hexSize = 40.0;
  final TransformationController _transformationController =
      TransformationController();

  HexTile? hoverTile;

  double _currentScale = 1.0;

  final List<_NotificationItem> _notifications = [];

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

  void _showNotification(String message) {
    if (!mounted) return;
    final item = _NotificationItem(
      id:
          DateTime.now().millisecondsSinceEpoch.toString() +
          math.Random().nextInt(1000).toString(),
      message: message,
    );
    setState(() {
      _notifications.add(item);
    });
  }

  void _removeNotification(String id) {
    if (!mounted) return;
    setState(() {
      _notifications.removeWhere((n) => n.id == id);
    });
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
        _showNotification('Map loaded successfully');
      } catch (e) {
        _showNotification('Error loading map: $e');
      }
    }
  }

  void _centerAndScaleMap(HexMap map) {
    if (map.layers.isEmpty) return;

    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    bool hasTiles = false;

    for (var layer in map.layers) {
      for (var region in layer.regions) {
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
    }

    if (!hasTiles) return;

    minX -= hexSize * 2;
    maxX += hexSize * 2;
    minY -= hexSize * 2;
    maxY += hexSize * 2;

    double mapWidth = maxX - minX;
    double mapHeight = maxY - minY;

    if (mapWidth == 0 || mapHeight == 0) return;

    final viewportWidth =
        MediaQuery.of(context).size.width -
        600; // 280 (Hierarchy) + 320 (Properties)
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

    _transformationController.value = Matrix4.diagonal3Values(
      scale,
      scale,
      scale,
    )..setTranslationRaw(targetX, targetY, 0.0);
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
      _showNotification('Map saved successfully');
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
        _showNotification('Please select a region in the Inspector first.');
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
        title: Row(
          children: [
            Icon(Icons.hexagon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            const Text(
              'Hex Grid Mapmaker',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            height: 1,
          ),
        ),
        actions: [
          _buildTopBarSwitch(
            context,
            label: 'Grid',
            value: state.showGrid,
            onChanged: (val) => state.setShowGrid(val),
          ),
          const SizedBox(width: 16),
          _buildTopBarDropdown(
            context,
            label: 'Labels',
            value: state.labelDisplay,
            items: ['None', 'ID', 'Name'],
            onChanged: (val) {
              if (val != null) state.setLabelDisplay(val);
            },
          ),
          const SizedBox(width: 24),
          _buildTopBarActionButton(
            context,
            icon: Icons.screen_rotation,
            tooltip: 'Toggle Orientation',
            onPressed: () => _toggleOrientation(state),
          ),
          const SizedBox(width: 8),
          _buildTopBarActionButton(
            context,
            icon: Icons.folder_open,
            tooltip: 'Load JSON',
            onPressed: () => _loadMap(state),
          ),
          const SizedBox(width: 8),
          _buildTopBarActionButton(
            context,
            icon: Icons.save,
            tooltip: 'Save JSON',
            onPressed: () => _saveMap(state),
            isPrimary: true,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          const HierarchyPanel(),
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
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 24.0),
                    child: ToolPalette(),
                  ),
                ),
                Positioned(
                  right: 24,
                  bottom: 80,
                  width: 320,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: _notifications.map((item) {
                      return _NotificationOverlay(
                        key: ValueKey(item.id),
                        item: item,
                        onDismissed: () => _removeNotification(item.id),
                      );
                    }).toList(),
                  ),
                ),
                Positioned(
                  right: 24,
                  bottom: 24,
                  child: FloatingActionButton(
                    mini: true,
                    elevation: 4,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.85),
                    foregroundColor: Colors.white,
                    onPressed: () => _centerAndScaleMap(state.hexMap),
                    tooltip: 'Recenter Map',
                    child: const Icon(Icons.center_focus_strong),
                  ),
                ),
              ],
            ),
          ),
          const PropertiesPanel(),
        ],
      ),
    );
  }

  Widget _buildTopBarSwitch(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.white70,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 24,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildTopBarDropdown(
    BuildContext context, {
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.white70,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              style: const TextStyle(fontSize: 13, color: Colors.white),
              items: items.map((String val) {
                return DropdownMenuItem<String>(value: val, child: Text(val));
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBarActionButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isPrimary
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onPressed,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: isPrimary ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationItem {
  final String id;
  final String message;

  _NotificationItem({required this.id, required this.message});
}

class _NotificationOverlay extends StatefulWidget {
  final _NotificationItem item;
  final VoidCallback onDismissed;

  const _NotificationOverlay({
    super.key,
    required this.item,
    required this.onDismissed,
  });

  @override
  State<_NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<_NotificationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _opacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    Future.delayed(const Duration(seconds: 4), () async {
      if (mounted) {
        await _controller.reverse();
        widget.onDismissed();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      axisAlignment: -1.0,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _opacity,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.item.message,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
