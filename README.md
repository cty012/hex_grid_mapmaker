# Hex Grid Mapmaker

A powerful, modern, hierarchical Hexagonal Grid Map Editor built with Flutter. 

Hex Grid Mapmaker allows you to design complex grid-based maps using a multi-layered approach. You can draw base geographical regions by selecting raw hex tiles, and then construct higher-level political or abstract boundaries by grouping those lower regions together in subsequent layers.

## Features

- **Hierarchical Layering**: Build your map from the ground up. Layer 0 handles raw hex tiles, while Layer N constructs macro-regions by logically grouping child regions from Layer N-1.
- **Smart Label Placement**: Features a custom Dart implementation of the **Polylabel** algorithm to calculate the true Pole of Inaccessibility. This guarantees that text labels are drawn perfectly in the visual center of complex, non-convex, or disjointed regions.
- **Advanced Editing Tools**: Draw, Erase, and Select regions seamlessly. The grid supports both *pointy-topped* and *flat-topped* orientations.
- **Robust Properties Inspector**: Fully editable region names, dynamic key-value attributes, and globally-validated Region IDs. Changing a Region ID automatically cascades and safely updates any references to it in the map hierarchy.
- **Professional UI/UX**: Designed with a sleek, dark-themed interface, featuring smooth animated notifications, interactive hover strokes, pulse animations, and a responsive workspace that auto-scales the map bounds.
- **Save & Load**: Serialize your entire map hierarchy and attributes into a clean, lightweight JSON format.

## Getting Started

### Prerequisites
Make sure you have the Flutter SDK installed on your system.

### Running Locally
To launch the editor (Web or Desktop recommended):

```bash
flutter pub get
flutter run -d chrome
```

## Project Architecture

- **`lib/models/hex_models.dart`**: Core data structures including `HexMap`, `HexLayer`, `HexRegion`, and `HexTile`.
- **`lib/state/app_state.dart`**: Centralized Provider state management. Handles the logic for multi-layer hierarchy editing, cross-layer ID propagation, boundary calculations, and JSON serialization.
- **`lib/ui/`**: Contains the modern user interface components:
  - `editor_screen.dart`: The main workspace managing the InteractiveViewer and animated overlays.
  - `hex_painter.dart`: The custom rendering pipeline for drawing regions, boundaries, grid lines, and labels.
  - `hierarchy_panel.dart` & `properties_panel.dart`: The side panels for managing layers and region metadata.
- **`lib/utils/polylabel.dart`**: Core mathematical utilities for continuous-space label placement inside polygon boundaries.

## Building for Release

To compile an optimized, standalone release version of the application, run one of the following commands depending on your target platform:

**For Windows Desktop (Standalone `.exe`):**
```bash
flutter build windows --release
```
*The compiled executable will be located in `build\windows\x64\runner\Release`.*

**For macOS (Standalone `.app`):**
```bash
flutter build macos --release
```
*Note: You must run this command on a Mac. The compiled app will be located in `build/macos/Build/Products/Release/`.*

**For Linux (Standalone executable):**
```bash
flutter build linux --release
```
*Note: You must run this command on a Linux machine. The compiled executable will be located in `build/linux/x64/release/bundle/`.*

**For Web (HTML/JS/CSS bundle):**
```bash
flutter build web --release
```
*The compiled web files will be located in the `build/web/` directory. You can host these on any static web server.*
