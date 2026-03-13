import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'agent_client.dart';
import 'vibe_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AgentClientProvider(),
      child: MaterialApp(
        title: 'Vibe 指挥中心',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          // 赛博朋克黑绿配色
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00FF41),
            brightness: Brightness.dark,
            primary: const Color(0xFF00FF41),
            surface: const Color(0xFF121212),
          ),
          scaffoldBackgroundColor: const Color(0xFF0A0A0A),
          cardTheme: CardTheme(
            color: const Color(0xFF1E1E1E),
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF2A2A2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00FF41), width: 1),
            ),
          ),
        ),
        home: const VibeScreen(),
      ),
    ),
  );
}
