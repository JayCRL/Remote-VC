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
          // 暖色调配置：琥珀金与暖深灰
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFFB300), // Amber 600
            brightness: Brightness.dark,
            primary: const Color(0xFFFFB300),
            secondary: const Color(0xFFFF8F00),
            surface: const Color(0xFF1A1A1A),
          ),
          scaffoldBackgroundColor: const Color(0xFF121212),
          cardTheme: CardTheme(
            color: const Color(0xFF222222),
            elevation: 4,
            shadowColor: Colors.black.withOpacity(0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF2D2D2D),
            labelStyle: const TextStyle(color: Color(0xFFFFB300)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFFFB300), width: 1.5),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        home: const VibeScreen(),
      ),
    ),
  );
}
