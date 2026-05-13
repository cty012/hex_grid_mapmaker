import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/enums.dart';
import 'package:hex_grid_mapmaker/state/editor_state.dart';
import 'package:provider/provider.dart';

/// Floating toolbar at the bottom of the canvas for switching editor tools.
///
/// Only watches [EditorState] — it doesn't depend on map data at all,
/// so changing tools never triggers a map data rebuild.
class ToolPalette extends StatelessWidget {
  const ToolPalette({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorState>();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            spreadRadius: 2,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTool(context, editor,
              tool: Tool.select, icon: Icons.ads_click, tooltip: 'Select Region'),
          const SizedBox(width: 8),
          _buildTool(context, editor,
              tool: Tool.draw, icon: Icons.brush, tooltip: 'Draw Tiles'),
          const SizedBox(width: 8),
          _buildTool(context, editor,
              tool: Tool.erase,
              icon: Icons.cleaning_services,
              tooltip: 'Erase Tiles'),
        ],
      ),
    );
  }

  Widget _buildTool(BuildContext context, EditorState editor,
      {required Tool tool, required IconData icon, required String tooltip}) {
    final isSelected = editor.activeTool == tool;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => editor.setTool(tool),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Icon(icon,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white54,
                size: 24),
          ),
        ),
      ),
    );
  }
}
