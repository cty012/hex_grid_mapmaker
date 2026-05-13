import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/state/editor_state.dart';
import 'package:hex_grid_mapmaker/state/map_state.dart';
import 'package:provider/provider.dart';

/// Left sidebar panel showing the layer/region tree structure.
///
/// Provides controls to:
/// - Switch between layers via a dropdown.
/// - Add/delete layers.
/// - Add/delete/select regions within the active layer.
///
/// Watches both [MapState] (for region/layer data) and [EditorState]
/// (for active layer/region selection).
class HierarchyPanel extends StatelessWidget {
  const HierarchyPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final mapState = context.watch<MapState>();
    final editor = context.watch<EditorState>();

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          const Divider(height: 1),
          _buildLayerControls(context, mapState, editor),
          const Divider(height: 1),
          _buildRegionList(context, mapState, editor),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Icon(Icons.layers, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Hierarchy',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildLayerControls(
      BuildContext context, MapState mapState, EditorState editor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: editor.activeLayerIndex,
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  items: mapState.hexMap.layers.map((l) {
                    return DropdownMenuItem<int>(
                      value: l.index,
                      child: Text('Layer ${l.index}',
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) editor.setActiveLayer(val);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                onPressed: () {
                  final newIndex = mapState.addLayer();
                  editor.setActiveLayer(newIndex);
                },
                tooltip: 'Add Layer',
                style: IconButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: Colors.redAccent),
                onPressed: () => _confirmDeleteLayer(context, mapState, editor),
                tooltip: 'Delete Layer',
                style: IconButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRegionList(
      BuildContext context, MapState mapState, EditorState editor) {
    final activeLayer = mapState.hexMap.getLayer(editor.activeLayerIndex);
    final regions = activeLayer?.regions ?? [];

    return Expanded(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Regions',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 0.5,
                    )),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: () {
                    final newId =
                        mapState.addRegion(editor.activeLayerIndex, 'New Region');
                    editor.setActiveRegion(newId);
                  },
                  tooltip: 'Add Region',
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: regions.length,
              itemBuilder: (context, index) {
                final region = regions[index];
                final isSelected = region.id == editor.activeRegionId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: isSelected
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => editor.setActiveRegion(region.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.hexagon_outlined,
                                size: 16,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white54),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(region.name,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white70,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Text(region.id,
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.white38)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  size: 16, color: Colors.white38),
                              onPressed: () => _confirmDeleteRegion(
                                  context, mapState, editor, region.id, region.name),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteLayer(
      BuildContext context, MapState mapState, EditorState editor) async {
    final layerIndex = editor.activeLayerIndex;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Layer'),
        content: Text(
            'Are you sure you want to delete Layer $layerIndex?\nThis action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (result == true) {
      mapState.deleteLayer(layerIndex);
      final newIndex = (layerIndex - 1).clamp(0, mapState.hexMap.layers.length - 1);
      editor.setActiveLayer(newIndex);
    }
  }

  Future<void> _confirmDeleteRegion(BuildContext context, MapState mapState,
      EditorState editor, String id, String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Region'),
        content: Text(
            'Are you sure you want to delete region "$name"?\nThis action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (result == true) {
      mapState.deleteRegion(id, editor.activeLayerIndex);
      if (editor.activeRegionId == id) editor.setActiveRegion(null);
    }
  }
}
