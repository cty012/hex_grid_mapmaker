import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/enums.dart';

/// UI-only transient state: tool selection, active region/layer, and display options.
///
/// This class is separated from [MapState] so that toggling the grid,
/// switching tools, or changing the selected region does NOT trigger a
/// rebuild of widgets that only depend on the map data (and vice versa).
///
/// Provided as a [ChangeNotifierProvider] in `main.dart`.
class EditorState extends ChangeNotifier {
  /// The currently active editor tool (select, draw, or erase).
  Tool activeTool = Tool.select;

  /// The ID of the currently selected region, or null if nothing is selected.
  String? activeRegionId;

  /// The index of the layer currently being viewed/edited.
  int activeLayerIndex = 0;

  /// Whether the hex grid overlay is visible on the canvas.
  bool showGrid = true;

  /// What text label to display inside each region (none, ID, or name).
  LabelDisplay labelDisplay = LabelDisplay.none;

  /// Switches the active tool and notifies listeners.
  void setTool(Tool tool) {
    activeTool = tool;
    notifyListeners();
  }

  /// Selects a region by ID, or deselects if null.
  void setActiveRegion(String? id) {
    activeRegionId = id;
    notifyListeners();
  }

  /// Switches the active layer. Also clears the region selection since
  /// region IDs are layer-specific in the context of the hierarchy panel.
  void setActiveLayer(int index) {
    activeLayerIndex = index;
    activeRegionId = null;
    notifyListeners();
  }

  /// Toggles the hex grid overlay visibility.
  void setShowGrid(bool val) {
    showGrid = val;
    notifyListeners();
  }

  /// Changes the label display mode for all regions on the canvas.
  void setLabelDisplay(LabelDisplay val) {
    labelDisplay = val;
    notifyListeners();
  }
}
