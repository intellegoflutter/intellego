import 'package:flutter/material.dart';

import '../features/library/library_screen.dart';

class IntellegoApp extends StatelessWidget {
  const IntellegoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Intellego',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const LibraryScreen(),
  );
}
