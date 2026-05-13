import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/enums.dart';
import 'package:hex_grid_mapmaker/models/hex_map.dart';
import 'package:hex_grid_mapmaker/models/hex_tile.dart';
import 'package:hex_grid_mapmaker/services/hex_geometry.dart' as geo;
import 'package:hex_grid_mapmaker/state/editor_state.dart';
import 'package:hex_grid_mapmaker/state/map_state.dart';
import 'package:hex_grid_mapmaker/ui/hex_painter.dart';
import 'package:hex_grid_mapmaker/ui/hierarchy_panel.dart';
import 'package:hex_grid_mapmaker/ui/properties_panel.dart';
import 'package:hex_grid_mapmaker/ui/tool_palette.dart';
import 'package:hex_grid_mapmaker/utils/file_saver.dart';
import 'package:provider/provider.dart';

/// The main application screen containing the hex canvas and all panels.
///
/// ## Layout Structure
///
/// ```
/// ┌─────────────┬──────────────────────────┬────────────────┐
/// │             │        AppBar            │                │
/// │  Hierarchy  ├──────────────────────────┤  Properties    │
/// │  Panel      │     Interactive Canvas   │  Panel         │
/// │  (280px)    │     (InteractiveViewer)   │  (320px)       │
/// │             │                          │                │
/// │             │     [ToolPalette]         │                │
/// └─────────────┴──────────────────────────┴────────────────┘
/// ```
///
/// ## Responsibilities
///
/// - Hosts the [InteractiveViewer] with pan/zoom and a 10000×10000 canvas.
/// - Converts mouse events to hex coordinates via [hex_geometry.dart].
/// - Dispatches tool actions (select/draw/erase) through [MapState]/[EditorState].
/// - Handles file I/O (load/save JSON) and toast notifications.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with SingleTickerProviderStateMixin {
  /// Pixel radius of each hex tile (constant across the session).
  final double hexSize = 40.0;

  /// Controls pan/zoom of the InteractiveViewer.
  final TransformationController _transformationController =
      TransformationController();

  HexTile? hoverTile;              // Tile under cursor for hover highlight.
  double _currentScale = 1.0;       // Cached zoom level for stroke scaling.
  final List<_NotificationItem> _notifications = []; // Active toast stack.

  late final AnimationController _pulseController;  // Drives selection glow.
  late final Animation<double> _pulseAnimation;      // 0.3 → 1.0 opacity.

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  /// Updates cached scale when the user pinch-zooms or scroll-zooms.
  void _onTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (scale != _currentScale) setState(() => _currentScale = scale);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Shows a temporary toast notification at the bottom-right of the canvas.
  void _showNotification(String message) {
    if (!mounted) return;
    setState(() {
      _notifications.add(_NotificationItem(
        id: '${DateTime.now().millisecondsSinceEpoch}${math.Random().nextInt(1000)}',
        message: message,
      ));
    });
  }

  void _removeNotification(String id) {
    if (!mounted) return;
    setState(() => _notifications.removeWhere((n) => n.id == id));
  }

  /// Toggles hex orientation between pointy-topped and flat-topped.
  void _toggleOrientation(MapState mapState) {
    mapState.hexMap.orientation =
        mapState.hexMap.orientation == MapOrientation.pointyTopped
            ? MapOrientation.flatTopped
            : MapOrientation.pointyTopped;
    mapState.forceUpdate();
  }

  /// Opens a file picker for JSON maps, deserializes, and loads into state.
  Future<void> _loadMap(MapState mapState, EditorState editor) async {
    final result = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['json'], withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;

    if (file.bytes == null) {
      _showNotification('Error: could not read file data');
      return;
    }
    final content = utf8.decode(file.bytes!);

    try {
      final map = HexMap.fromJson(jsonDecode(content));
      mapState.loadMap(map);
      editor.setActiveLayer(0);
      _centerAndScaleMap(map);
      _showNotification('Map loaded successfully');
    } catch (e) {
      _showNotification('Error loading map: $e');
    }
  }


  /// Computes the bounding box of all tiles and adjusts the InteractiveViewer
  /// transform to center and fit the map within the visible viewport.
  void _centerAndScaleMap(HexMap map) {
    if (map.layers.isEmpty) return;

    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    bool hasTiles = false;

    for (final layer in map.layers) {
      for (final region in layer.regions) {
        for (final tile in region.tiles ?? <HexTile>[]) {
          hasTiles = true;
          final pos = geo.hexToPixel(map.orientation, hexSize, tile);
          if (pos.dx < minX) minX = pos.dx;
          if (pos.dx > maxX) maxX = pos.dx;
          if (pos.dy < minY) minY = pos.dy;
          if (pos.dy > maxY) maxY = pos.dy;
        }
      }
    }
    if (!hasTiles) return;

    minX -= hexSize * 2;
    maxX += hexSize * 2;
    minY -= hexSize * 2;
    maxY += hexSize * 2;
    final mapWidth = maxX - minX, mapHeight = maxY - minY;
    if (mapWidth == 0 || mapHeight == 0) return;

    final vpWidth = MediaQuery.of(context).size.width - 600;
    final vpHeight = MediaQuery.of(context).size.height - kToolbarHeight;
    final scale = math.min(vpWidth / mapWidth, vpHeight / mapHeight).clamp(0.1, 2.0);
    final cx = 5000 + (minX + maxX) / 2, cy = 5000 + (minY + maxY) / 2;

    _transformationController.value = Matrix4.diagonal3Values(scale, scale, scale)
      ..setTranslationRaw((vpWidth / 2) - cx * scale, (vpHeight / 2) - cy * scale, 0);
  }

  /// Serializes the current map to JSON and triggers a file download.
  Future<void> _saveMap(MapState mapState) async {
    try {
      await saveFile('map.json', jsonEncode(mapState.hexMap.toJson()));
      _showNotification('Map saved successfully');
    } catch (e) {
      _showNotification('Error saving map: $e');
    }
  }

  /// Converts mouse position to hex coordinates and updates hover state.
  void _onHover(Offset pos, Size canvasSize, MapState mapState) {
    final pixel = Offset(pos.dx - canvasSize.width / 2, pos.dy - canvasSize.height / 2);
    final tile = geo.pixelToHex(mapState.hexMap.orientation, hexSize, pixel);
    if (hoverTile != tile) setState(() => hoverTile = tile);
  }

  /// Handles a canvas tap by dispatching the appropriate tool action.
  void _onTap(Offset pos, Size canvasSize, MapState mapState, EditorState editor) {
    final pixel = Offset(pos.dx - canvasSize.width / 2, pos.dy - canvasSize.height / 2);
    final tile = geo.pixelToHex(mapState.hexMap.orientation, hexSize, pixel);

    switch (editor.activeTool) {
      case Tool.select:
        final region = mapState.getRegionAtTile(tile, editor.activeLayerIndex);
        editor.setActiveRegion(region?.id);
      case Tool.draw:
        if (editor.activeRegionId == null) {
          _showNotification('Please select a region in the Inspector first.');
          return;
        }
        mapState.addTileToRegion(tile, editor.activeLayerIndex, editor.activeRegionId!);
      case Tool.erase:
        mapState.removeTile(tile, editor.activeLayerIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    const canvasSize = Size(10000, 10000);
    final mapState = context.watch<MapState>();
    final editor = context.watch<EditorState>();

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.hexagon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          const Text('Hex Grid Mapmaker',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 0.5)),
        ]),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest, height: 1),
        ),
        actions: [
          _buildSwitch(context, label: 'Grid', value: editor.showGrid,
              onChanged: (val) => editor.setShowGrid(val)),
          const SizedBox(width: 16),
          _buildLabelDropdown(context, editor),
          const SizedBox(width: 24),
          _buildAction(context, icon: Icons.screen_rotation, tooltip: 'Toggle Orientation',
              onPressed: () => _toggleOrientation(mapState)),
          const SizedBox(width: 8),
          _buildAction(context, icon: Icons.folder_open, tooltip: 'Load JSON',
              onPressed: () => _loadMap(mapState, editor)),
          const SizedBox(width: 8),
          _buildAction(context, icon: Icons.save, tooltip: 'Save JSON',
              onPressed: () => _saveMap(mapState), isPrimary: true),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(children: [
        const HierarchyPanel(),
        Expanded(
          child: Stack(children: [
            InteractiveViewer(
              transformationController: _transformationController,
              constrained: false,
              minScale: 0.1,
              maxScale: 5.0,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: MouseRegion(
                onHover: (e) => _onHover(e.localPosition, canvasSize, mapState),
                onExit: (_) => setState(() => hoverTile = null),
                child: GestureDetector(
                  onTapUp: (d) =>
                      _onTap(d.localPosition, canvasSize, mapState, editor),
                  child: CustomPaint(
                    size: canvasSize,
                    painter: HexPainter(
                      mapState: mapState,
                      editorState: editor,
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
                  padding: EdgeInsets.only(bottom: 24.0), child: ToolPalette()),
            ),
            Positioned(
              right: 24, bottom: 80, width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _notifications.map((item) => _NotificationOverlay(
                    key: ValueKey(item.id),
                    item: item,
                    onDismissed: () => _removeNotification(item.id))).toList(),
              ),
            ),
            Positioned(
              right: 24, bottom: 24,
              child: FloatingActionButton(
                mini: true,
                elevation: 4,
                backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                foregroundColor: Colors.white,
                onPressed: () => _centerAndScaleMap(mapState.hexMap),
                tooltip: 'Recenter Map',
                child: const Icon(Icons.center_focus_strong),
              ),
            ),
          ]),
        ),
        const PropertiesPanel(),
      ]),
    );
  }

  Widget _buildSwitch(BuildContext context,
      {required String label, required bool value, required ValueChanged<bool> onChanged}) {
    return Row(children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white70)),
      const SizedBox(width: 8),
      SizedBox(
          height: 24,
          child: Switch(value: value, onChanged: onChanged,
              activeThumbColor: Theme.of(context).colorScheme.primary)),
    ]);
  }

  Widget _buildLabelDropdown(BuildContext context, EditorState editor) {
    return Row(children: [
      const Text('Labels',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white70)),
      const SizedBox(width: 8),
      Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<LabelDisplay>(
            value: editor.labelDisplay,
            isDense: true,
            icon: const Icon(Icons.arrow_drop_down, size: 18),
            style: const TextStyle(fontSize: 13, color: Colors.white),
            items: const [
              DropdownMenuItem(value: LabelDisplay.none, child: Text('None')),
              DropdownMenuItem(value: LabelDisplay.id, child: Text('ID')),
              DropdownMenuItem(value: LabelDisplay.name, child: Text('Name')),
            ],
            onChanged: (val) {
              if (val != null) editor.setLabelDisplay(val);
            },
          ),
        ),
      ),
    ]);
  }

  Widget _buildAction(BuildContext context,
      {required IconData icon, required String tooltip,
      required VoidCallback onPressed, bool isPrimary = false}) {
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
            width: 36, height: 36, alignment: Alignment.center,
            child: Icon(icon, size: 18,
                color: isPrimary ? Colors.white : Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _NotificationItem {
  final String id, message;
  _NotificationItem({required this.id, required this.message});
}

class _NotificationOverlay extends StatefulWidget {
  final _NotificationItem item;
  final VoidCallback onDismissed;
  const _NotificationOverlay({super.key, required this.item, required this.onDismissed});

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
        vsync: this, duration: const Duration(milliseconds: 300));
    _opacity = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
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
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.info_outline, size: 18,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(widget.item.message,
                          style: const TextStyle(fontSize: 14))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
