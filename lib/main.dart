import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hex_grid_mapmaker/state/app_state.dart';
import 'package:hex_grid_mapmaker/ui/editor_screen.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
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
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5E81AC),
          secondary: Color(0xFF81A1C1),
          surface: Color(0xFF161B22),
          surfaceContainerHighest: Color(0xFF21262D),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
      ),
      home: const EditorScreen(),
    );
  }
}
