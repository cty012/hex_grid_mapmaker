/// Application entry point for the Hex Grid Mapmaker.
///
/// Sets up the [MultiProvider] with two independent state objects:
/// - [MapState]: Data mutations (tiles, regions, layers, boundaries).
/// - [EditorState]: UI-only state (tool selection, active region, grid visibility).
///
/// Splitting state this way prevents UI-only changes (e.g. toggling the grid)
/// from triggering a full map data rebuild, and vice versa.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hex_grid_mapmaker/state/editor_state.dart';
import 'package:hex_grid_mapmaker/state/map_state.dart';
import 'package:hex_grid_mapmaker/ui/editor_screen.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MapState()),
        ChangeNotifierProvider(create: (_) => EditorState()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hex Grid Mapmaker',
      // Nord-inspired dark theme: muted blues with high-contrast surface layers.
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5E81AC), // Nord frost blue
          secondary: Color(0xFF81A1C1), // Nord lighter blue
          surface: Color(0xFF161B22), // GitHub-dark panel background
          surfaceContainerHighest: Color(0xFF21262D), // Input/card background
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D1117), // GitHub-dark base
      ),
      home: const EditorScreen(),
    );
  }
}
