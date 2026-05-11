import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/state/app_state.dart';
import 'package:provider/provider.dart';

class ToolPalette extends StatelessWidget {
  const ToolPalette({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Positioned(
      left: 16,
      top: 16,
      child: Card(
        elevation: 4,
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTool(
              context,
              state,
              tool: 'select',
              icon: Icons.ads_click,
              tooltip: 'Select Region',
            ),
            _buildTool(
              context,
              state,
              tool: 'draw',
              icon: Icons.brush,
              tooltip: 'Draw Tiles',
            ),
            _buildTool(
              context,
              state,
              tool: 'erase',
              icon: Icons.cleaning_services,
              tooltip: 'Erase Tiles',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTool(
    BuildContext context,
    AppState state, {
    required String tool,
    required IconData icon,
    required String tooltip,
  }) {
    final isSelected = state.activeTool == tool;
    return IconButton(
      icon: Icon(icon, color: isSelected ? Colors.blueAccent : Colors.white54),
      tooltip: tooltip,
      onPressed: () => state.setTool(tool),
    );
  }
}
