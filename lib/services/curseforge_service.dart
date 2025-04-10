import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/sound.dart';
import 'package:archive/archive_io.dart';
import 'package:permission_handler/permission_handler.dart';

class CurseForgeService {
  static final CurseForgeService _instance = CurseForgeService._internal();
  late String _curseForgePath;
  bool _isInitialized = false;

  factory CurseForgeService() {
    return _instance;
  }

  CurseForgeService._internal();

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await _initPath();
      _isInitialized = true;
    }
  }

  Future<void> _initPath() async {
    final homeDir = Platform.environment['USERPROFILE'] ?? '';
    _curseForgePath = path.join(homeDir, 'curseforge', 'minecraft', 'Instances');
  }

  /// Normalise un chemin selon la plateforme
  String _normalizePath(String filePath) {
    return path.normalize(filePath);
  }

  /// Joint des segments de chemin de façon compatible multiplateforme
  String _joinPath(List<String> parts) {
    return path.joinAll(parts);
  }

  /// Vérifie les permissions nécessaires (à appeler au démarrage de l'application)
  Future<void> checkPermissions() async {
    try {
      // Demander les permissions de fichier selon la plateforme
      if (Platform.isAndroid || Platform.isIOS) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          throw Exception('Accès aux fichiers refusé');
        }
      }
    } catch (e) {
      debugPrint('Erreur lors de la vérification des permissions: $e');
    }
  }

  Future<List<String>> getInstances() async {
    await _ensureInitialized();
    try {
      final directory = Directory(_curseForgePath);
      if (!await directory.exists()) {
        return [];
      }

      return await directory.list().where((entity) => entity is Directory).map((entity) => path.basename(entity.path)).where((name) => name.toLowerCase() != 'curseforge').toList();
    } catch (e) {
      debugPrint('Erreur lors de la lecture des instances CurseForge: $e');
      return [];
    }
  }

  Future<List<String>> getResourcePacks(String instanceName) async {
    await _ensureInitialized();
    try {
      final resourcePacksPath = path.join(await getInstancePath(instanceName), 'resourcepacks');
      final directory = Directory(resourcePacksPath);

      if (!await directory.exists()) {
        return [];
      }

      return await directory.list().where((entity) => entity is Directory || entity.path.endsWith('.zip')).map((entity) => path.basename(entity.path)).toList();
    } catch (e) {
      debugPrint('Erreur lors de la lecture des resource packs: $e');
      return [];
    }
  }

  Future<String> getInstancePath(String instanceName) async {
    await _ensureInitialized();
    return path.join(_curseForgePath, instanceName);
  }

  Future<String> getCurseForgePath() async {
    await _ensureInitialized();
    return _curseForgePath;
  }

  Future<List<Sound>> getResourcePackSounds(String instanceName, String resourcePackName) async {
    await _ensureInitialized();
    try {
      // Utiliser le dossier extrait plutôt que le .zip
      final instancePath = await getInstancePath(instanceName);
      final extractedPath = path.join(instancePath, 'extracted', resourcePackName);
      final soundsJsonPath = path.join(extractedPath, 'assets', 'minecraft', 'sounds.json');
      final soundsDirPath = path.join(extractedPath, 'assets', 'minecraft', 'sounds');

      final List<Sound> sounds = [];

      // Lire le fichier sounds.json
      final soundsJsonFile = File(soundsJsonPath);
      if (await soundsJsonFile.exists()) {
        final jsonContent = await soundsJsonFile.readAsString();
        final soundsData = jsonDecode(jsonContent) as Map<String, dynamic>;

        soundsData.forEach((eventName, eventData) {
          if (eventData is Map && eventData.containsKey('sounds')) {
            final soundList = eventData['sounds'] as List;
            for (var sound in soundList) {
              if (sound is String) {
                sounds.add(Sound(
                  name: sound,
                  path: sound,
                  category: eventName.split('.')[0],
                ));
              }
            }
          }
        });
      }

      // Explorer le dossier sounds pour trouver les fichiers .ogg
      final soundsDir = Directory(soundsDirPath);
      if (await soundsDir.exists()) {
        await for (var entity in soundsDir.list(recursive: true)) {
          if (entity is File && entity.path.endsWith('.ogg')) {
            final relativePath = path.relative(entity.path, from: soundsDirPath).replaceAll(r'\', '/');
            final soundName = relativePath.replaceAll('.ogg', '');

            // Vérifier si le son existe déjà dans la liste
            if (!sounds.any((s) => s.path == soundName)) {
              sounds.add(Sound(
                name: soundName.split('/').last,
                path: soundName,
                category: soundName.split('/').first,
                isCustom: true,
              ));
            }
          }
        }
      }

      return sounds;
    } catch (e) {
      debugPrint('Erreur lors de la lecture des sons: $e');
      return [];
    }
  }

  Future<void> extractResourcePack(String instanceName, String resourcePackName) async {
    await _ensureInitialized();
    try {
      final resourcePackPath = path.join(await getInstancePath(instanceName), 'resourcepacks', resourcePackName);
      final destinationPath = path.join(await getInstancePath(instanceName), 'extracted', resourcePackName);

      // Vérifier si le dossier extrait existe déjà
      final destinationDir = Directory(destinationPath);
      if (await destinationDir.exists()) {
        // Vérifier si le dossier contient des fichiers
        final files = await destinationDir.list().toList();
        if (files.isNotEmpty) {
          return; // Skip extraction si le dossier existe et n'est pas vide
        }
      }

      // Vérifier si la source existe
      final source = File(resourcePackPath);
      final sourceDir = Directory(resourcePackPath);

      if (!(await source.exists()) && !(await sourceDir.exists())) {
        throw Exception('Resource pack non trouvé: $resourcePackPath');
      }

      // Préparer le dossier de destination
      if (await destinationDir.exists()) {
        // Supprimer le dossier existant pour éviter les conflits
        await destinationDir.delete(recursive: true);
      }

      await destinationDir.create(recursive: true);

      // Déterminer si la source est un dossier ou un fichier zip
      bool isDirectory = await sourceDir.exists();

      if (isDirectory) {
        // Si c'est un dossier, copier le contenu
        await _copyDirectory(sourceDir, destinationDir);
      } else {
        // Si c'est un fichier zip, l'extraire
        try {
          // Utiliser la bibliothèque archive pour extraire
          final bytes = await source.readAsBytes();
          final archive = ZipDecoder().decodeBytes(bytes);

          // Extraire tous les fichiers
          for (final file in archive) {
            final outputPath = path.join(destinationPath, file.name);
            if (file.isFile) {
              final outputFile = File(outputPath);
              await outputFile.parent.create(recursive: true);
              await outputFile.writeAsBytes(file.content as List<int>);
            } else {
              await Directory(outputPath).create(recursive: true);
            }
          }
        } catch (e) {
          throw Exception('Erreur lors de l\'extraction: $e');
        }
      }
    } catch (e) {
      debugPrint('Erreur lors de l\'extraction: $e');
      rethrow;
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (var entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDirectory = Directory(path.join(destination.path, path.basename(entity.path)));
        await newDirectory.create();
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy(path.join(destination.path, path.basename(entity.path)));
      }
    }
  }
}
