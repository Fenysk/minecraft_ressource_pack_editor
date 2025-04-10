import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CurseForgeService {
  static final CurseForgeService _instance = CurseForgeService._internal();
  late String _curseForgePath;

  factory CurseForgeService() {
    return _instance;
  }

  CurseForgeService._internal() {
    _initPath();
  }

  Future<void> _initPath() async {
    final homeDir = Platform.environment['USERPROFILE'] ?? '';
    _curseForgePath = '$homeDir\\curseforge\\minecraft\\Instances';
  }

  Future<List<String>> getInstances() async {
    try {
      final directory = Directory(_curseForgePath);
      if (!await directory.exists()) {
        return [];
      }
      return await directory.list().where((entity) => entity is Directory).map((entity) => entity.path.split('\\').last).toList();
    } catch (e) {
      print('Error reading CurseForge instances: $e');
      return [];
    }
  }

  String getInstancePath(String instanceName) {
    return '$_curseForgePath\\$instanceName';
  }

  String getCurseForgePath() {
    return _curseForgePath;
  }
}
