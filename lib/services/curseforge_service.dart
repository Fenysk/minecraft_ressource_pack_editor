import 'dart:io';
import 'dart:convert';
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
    _curseForgePath = '$homeDir\\curseforge\\minecraft\\Instances';
  }

  Future<List<String>> getInstances() async {
    await _ensureInitialized();
    try {
      final directory = Directory(_curseForgePath);
      if (!await directory.exists()) {
        return [];
      }
      return await directory.list().where((entity) => entity is Directory).map((entity) => entity.path.split('\\').last).where((name) => name.toLowerCase() != 'curseforge').toList();
    } catch (e) {
      print('Error reading CurseForge instances: $e');
      return [];
    }
  }

  Future<List<String>> getResourcePacks(String instanceName) async {
    await _ensureInitialized();
    try {
      final resourcePacksPath = '${await getInstancePath(instanceName)}\\resourcepacks';
      final directory = Directory(resourcePacksPath);

      if (!await directory.exists()) {
        return [];
      }

      return await directory.list().where((entity) => entity is Directory || entity.path.endsWith('.zip')).map((entity) => entity.path.split('\\').last).toList();
    } catch (e) {
      print('Error reading resource packs: $e');
      return [];
    }
  }

  Future<String> getInstancePath(String instanceName) async {
    await _ensureInitialized();
    return '$_curseForgePath\\$instanceName';
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
      final extractedPath = '$instancePath\\extracted\\$resourcePackName';
      final soundsJsonPath = '$extractedPath\\assets\\minecraft\\sounds.json';
      final soundsDirPath = '$extractedPath\\assets\\minecraft\\sounds';

      print('Lecture des sons depuis le dossier extrait: $extractedPath');

      final List<Sound> sounds = [];

      // Lire le fichier sounds.json
      final soundsJsonFile = File(soundsJsonPath);
      if (await soundsJsonFile.exists()) {
        print('Fichier sounds.json trouvé: $soundsJsonPath');
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
      } else {
        print('Fichier sounds.json non trouvé: $soundsJsonPath');
      }

      // Explorer le dossier sounds pour trouver les fichiers .ogg
      final soundsDir = Directory(soundsDirPath);
      if (await soundsDir.exists()) {
        print('Dossier de sons trouvé: $soundsDirPath');
        await for (var entity in soundsDir.list(recursive: true)) {
          if (entity is File && entity.path.endsWith('.ogg')) {
            final relativePath = entity.path.substring(soundsDirPath.length + 1);
            final soundName = relativePath.replaceAll('\\', '/').replaceAll('.ogg', '');

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
      } else {
        print('Dossier de sons non trouvé: $soundsDirPath');
      }

      print('Nombre de sons trouvés: ${sounds.length}');
      return sounds;
    } catch (e) {
      print('Error reading resource pack sounds: $e');
      return [];
    }
  }

  Future<void> extractResourcePack(String instanceName, String resourcePackName) async {
    await _ensureInitialized();
    try {
      final resourcePackPath = '${await getInstancePath(instanceName)}\\resourcepacks\\$resourcePackName';
      final destinationPath = '${await getInstancePath(instanceName)}\\extracted\\$resourcePackName';

      print('Vérification du resource pack: $resourcePackName');
      print('Chemin source: $resourcePackPath');
      print('Chemin destination: $destinationPath');

      // Vérifier si le dossier extrait existe déjà
      final destinationDir = Directory(destinationPath);
      if (await destinationDir.exists()) {
        // Vérifier si le dossier contient des fichiers
        final files = await destinationDir.list().toList();
        if (files.isNotEmpty) {
          print('Le resource pack est déjà extrait (${files.length} fichiers/dossiers trouvés)');
          return; // Skip extraction si le dossier existe et n'est pas vide
        } else {
          print('Le dossier d\'extraction existe mais est vide, extraction nécessaire');
        }
      }

      // Vérifier si la source existe
      final source = File(resourcePackPath);
      final sourceDir = Directory(resourcePackPath);

      if (!(await source.exists()) && !(await sourceDir.exists())) {
        print('Source non trouvée: $resourcePackPath');
        return;
      }

      // Préparer le dossier de destination
      if (await destinationDir.exists()) {
        // Supprimer le dossier existant pour éviter les conflits
        await destinationDir.delete(recursive: true);
        print('Ancien dossier de destination supprimé.');
      }

      await destinationDir.create(recursive: true);
      print('Dossier de destination créé: $destinationPath');

      // Déterminer si la source est un dossier ou un fichier zip
      bool isDirectory = await sourceDir.exists();

      if (isDirectory) {
        // Si c'est un dossier, copier le contenu
        print('La source est un dossier, copie des fichiers...');
        await _copyDirectory(sourceDir, destinationDir);
        print('Copie du dossier terminée.');
      } else {
        // Si c'est un fichier zip, l'extraire
        print('La source est un fichier zip, extraction...');
        try {
          // Utiliser ZipFileEncoder/Decoder pour éviter les problèmes de permission
          final inputStream = source.openRead();
          List<int> bytes = [];
          await for (var chunk in inputStream) {
            bytes.addAll(chunk);
          }

          final archive = ZipDecoder().decodeBytes(bytes);

          for (final file in archive) {
            final filePath = '$destinationPath\\${file.name.replaceAll('/', '\\')}';
            if (file.isFile) {
              final data = file.content as List<int>;
              final outFile = File(filePath);
              await outFile.parent.create(recursive: true);
              await outFile.writeAsBytes(data);
              print('Fichier extrait: ${file.name}');
            } else {
              await Directory(filePath).create(recursive: true);
              print('Dossier créé: ${file.name}');
            }
          }
          print('Extraction terminée.');
        } catch (e) {
          print('Erreur lors de l\'extraction du zip: $e');
          // Essayer une approche alternative
          print('Tentative d\'extraction alternative...');
          try {
            await Process.run('powershell', [
              '-command',
              "Expand-Archive -Path '$resourcePackPath' -DestinationPath '$destinationPath' -Force"
            ]);
            print('Extraction alternative terminée.');
          } catch (e) {
            print('Erreur lors de l\'extraction alternative: $e');
          }
        }
      }

      print('Extraction/copie terminée. Dossier extrait: $destinationPath');
    } catch (e) {
      print('Erreur lors de l\'extraction du resource pack: $e');
    }
  }

  // Méthode pour copier un dossier et son contenu
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (var entity in source.list(recursive: false)) {
      final newPath = '${destination.path}\\${entity.path.split('\\').last}';

      if (entity is Directory) {
        final newDir = Directory(newPath);
        await newDir.create(recursive: true);
        await _copyDirectory(entity, newDir);
      } else if (entity is File) {
        await entity.copy(newPath);
        print('Fichier copié: ${entity.path}');
      }
    }
  }

  Future<void> checkPermissions() async {
    if (await Permission.storage.request().isGranted) {
      print('Permissions accordées.');
    } else {
      print('Permissions non accordées.');
    }
  }
}
