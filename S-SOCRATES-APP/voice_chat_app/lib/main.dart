import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'stage/robot_stage_screen.dart';
import 'package:voice_chat_app/services/api_config.dart';

// HomeScreen cũ vẫn available ở home_screen.dart nếu cần test
// import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.init();

  // Ưu tiên landscape cho tablet sân khấu
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);

  // Ẩn status bar để full-screen stage feel
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const SSocratesApp());
}

class SSocratesApp extends StatelessWidget {
  const SSocratesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'S-Socrates',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C8FF), // cyan accent
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF020B18),
        useMaterial3: true,
        fontFamily: 'Segoe UI',
      ),
      home: const RobotStageScreen(),
    );
  }
}
