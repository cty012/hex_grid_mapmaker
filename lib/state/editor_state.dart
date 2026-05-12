import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/enums.dart';

/// UI-only transient state: tool selection, active region, grid display.
class EditorState extends ChangeNotifier {
  Tool activeTool = Tool.select;
  String? activeRegionId;
  int activeLayerIndex = 0;
  bool showGrid = true;
  LabelDisplay labelDisplay = LabelDisplay.none;

  void setTool(Tool tool) {
    activeTool = tool;
    notifyListeners();
  }

  void setActiveRegion(String? id) {
    activeRegionId = id;
    notifyListeners();
  }

  void setActiveLayer(int index) {
    activeLayerIndex = index;
    activeRegionId = null;
    notifyListeners();
  }

  void setShowGrid(bool val) {
    showGrid = val;
    notifyListeners();
  }

  void setLabelDisplay(LabelDisplay val) {
    labelDisplay = val;
    notifyListeners();
  }
}
