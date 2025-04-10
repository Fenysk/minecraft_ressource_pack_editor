import 'package:flutter/material.dart';
import 'pages/curseforge_instances_page.dart';
import 'services/curseforge_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CurseForgeService().checkPermissions(); // Vérifie les permissions au démarrage
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minecraft Resource Pack Editor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const CurseForgeInstancesPage(),
    );
  }
}
