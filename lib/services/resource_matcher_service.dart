import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import '../models/resource_match.dart';

class MatcherProgress {
  final double progress; // 0.0 à 1.0
  final String message;
  final int current;
  final int total;

  MatcherProgress({
    required this.progress,
    required this.message,
    required this.current,
    required this.total,
  });
}

class ResourceMatcherService {
  /// Les types d'actions sonores que nous voulons associer
  final List<String> _actionTypes = [
    'break',
    'step',
    'place',
    'hit',
    'fall',
    'chime',
    'click',
    'dig',
    'chunk',
    'open',
    'close',
    'throw',
    'pickup'
  ];

  /// Logs d'opération
  final List<String> _logs = [];

  /// Stream pour suivre la progression
  final progressController = ValueNotifier<MatcherProgress?>(null);

  /// Récupérer les logs
  List<String> get logs => List.unmodifiable(_logs);

  void _log(String message) {
    print(message);
    _logs.add("${DateTime.now().toIso8601String().substring(11, 19)} - $message");
  }

  void _updateProgress({
    required double progress,
    required String message,
    required int current,
    required int total,
  }) {
    progressController.value = MatcherProgress(
      progress: progress,
      message: message,
      current: current,
      total: total,
    );
  }

  /// Associe des sons à des textures en se basant sur des motifs de noms et l'arborescence
  Future<List<ResourceMatch>> matchSoundsToTextures(String resourcePackPath) async {
    final List<ResourceMatch> matches = [];
    _logs.clear();

    try {
      _log("Démarrage de l'association textures-sons pour $resourcePackPath");

      // Récupérer tous les fichiers de texture
      _updateProgress(progress: 0.1, message: "Recherche des textures...", current: 0, total: 100);
      final textureDir = Directory('$resourcePackPath/assets/minecraft/textures');
      if (!textureDir.existsSync()) {
        _log('Dossier textures non trouvé: ${textureDir.path}');
        return [];
      }

      _updateProgress(progress: 0.2, message: "Recherche des sons...", current: 20, total: 100);
      final soundsDir = Directory('$resourcePackPath/assets/minecraft/sounds');
      if (!soundsDir.existsSync()) {
        _log('Dossier sons non trouvé: ${soundsDir.path}');
        return [];
      }

      // Récupérer tous les fichiers de texture
      _updateProgress(progress: 0.3, message: "Indexation des textures...", current: 30, total: 100);
      final List<FileSystemEntity> textureFiles = await _getFilesRecursively(textureDir, [
        '.png'
      ]);
      _log('Nombre de textures trouvées: ${textureFiles.length}');

      // Créer un index des textures par chemin relatif
      final Map<String, String> textureIndex = {};
      for (final textureFile in textureFiles) {
        final relativePath = path.relative(textureFile.path, from: textureDir.path).replaceAll('\\', '/');
        textureIndex[relativePath.toLowerCase()] = textureFile.path;
      }

      // Récupérer tous les fichiers de son
      _updateProgress(progress: 0.5, message: "Indexation des sons...", current: 50, total: 100);
      final List<FileSystemEntity> soundFiles = await _getFilesRecursively(soundsDir, [
        '.ogg',
        '.mp3',
        '.wav'
      ]);
      _log('Nombre de sons trouvés: ${soundFiles.length}');

      // Créer un index des sons par chemin relatif
      final Map<String, String> soundIndex = {};
      for (final soundFile in soundFiles) {
        final relativePath = path.relative(soundFile.path, from: soundsDir.path).replaceAll('\\', '/');
        soundIndex[relativePath.toLowerCase()] = soundFile.path;
      }

      // Pour chaque son, trouver les textures correspondantes avec priorités
      _updateProgress(progress: 0.6, message: "Analyse des correspondances...", current: 60, total: 100);

      int processedSounds = 0;
      final totalSounds = soundFiles.length;
      int matchCount = 0;

      final Map<String, List<String>> soundToTextures = {};

      for (final soundFile in soundFiles) {
        processedSounds++;

        if (processedSounds % 50 == 0 || processedSounds == totalSounds) {
          final progressPercent = 0.6 + (0.4 * (processedSounds / totalSounds));
          _updateProgress(progress: progressPercent, message: "Analyse son ${processedSounds}/${totalSounds}...", current: processedSounds, total: totalSounds);
        }

        final soundPath = soundFile.path;
        final relativeSoundPath = path.relative(soundPath, from: soundsDir.path).replaceAll('\\', '/');
        final soundNameWithoutExt = path.basenameWithoutExtension(soundPath);

        // Identifier le type d'action (break, step, etc.) si présent
        String? actionType;
        for (final action in _actionTypes) {
          if (soundNameWithoutExt.contains(action) || relativeSoundPath.contains(action)) {
            actionType = action;
            break;
          }
        }

        // Structures pour la priorité de matching
        final List<String> potentialMatches = [];
        final Map<String, int> matchScore = {};

        // Analyser le chemin du son pour trouver des patterns de matching
        final soundPathParts = relativeSoundPath.split('/');

        // Enlever l'extension et le numéro séquentiel s'il y en a (ex: break1.ogg -> break)
        final lastPart = soundPathParts.last;
        final baseNameClean = _removeSequentialNumber(path.basenameWithoutExtension(lastPart));

        // Récupérer le contexte: dossier parent, nom du son sans action
        final parentFolder = soundPathParts.length > 1 ? soundPathParts[soundPathParts.length - 2] : "";
        final grandParentFolder = soundPathParts.length > 2 ? soundPathParts[soundPathParts.length - 3] : "";

        // Extraire le nom de base du son sans l'action (ex: "amethyst/break1" -> "amethyst")
        String baseNameWithoutAction = baseNameClean;
        if (actionType != null) {
          baseNameWithoutAction = baseNameClean.replaceAll(actionType, '').trim();
        }

        // Si après avoir enlevé l'action le nom est vide, utiliser le dossier parent
        if (baseNameWithoutAction.isEmpty) {
          baseNameWithoutAction = parentFolder;
        }

        _log('Analyse du son: $relativeSoundPath (base: $baseNameWithoutAction, action: $actionType, parent: $parentFolder)');

        // Stratégies de matching par ordre de priorité:

        // Stratégie 1: Chemin direct équivalent (highest priority)
        // Ex: sounds/block/amethyst/break1.ogg -> textures/block/amethyst.png ou textures/block/amethyst_block.png
        List<String> directMatches = [];

        // Essai 1.1: Même chemin exact sans l'action et sans suffixe
        for (final texturePath in textureIndex.keys) {
          final texturePathParts = texturePath.split('/');
          if (texturePathParts.length < 2) continue;

          // Vérifier si les deux fichiers sont dans le même sous-répertoire (ex: block)
          final textureType = texturePathParts[0]; // ex: "block"
          final soundType = soundPathParts.length > 1 ? soundPathParts[0] : "";

          if (soundType.isNotEmpty && textureType == soundType) {
            // Vérifier si le nom de base est contenu dans le nom de la texture
            final textureName = path.basenameWithoutExtension(texturePath).toLowerCase();

            // Si le nom de base est contenu directement dans le nom de la texture
            if (textureName == baseNameWithoutAction.toLowerCase()) {
              directMatches.add(textureIndex[texturePath]!);
              matchScore[textureIndex[texturePath]!] = 100; // Score maximal
              _log('Match direct parfait: $relativeSoundPath -> $texturePath');
            }
            // Si le nom de base + 'block' est égal au nom de la texture (ex: amethyst -> amethyst_block)
            else if (textureName == '${baseNameWithoutAction.toLowerCase()}_block') {
              directMatches.add(textureIndex[texturePath]!);
              matchScore[textureIndex[texturePath]!] = 95; // Score presque maximal
              _log('Match direct avec suffixe _block: $relativeSoundPath -> $texturePath');
            }
            // Si le nom de base fait partie du nom de la texture
            else if (textureName.contains(baseNameWithoutAction.toLowerCase()) && baseNameWithoutAction.length > 3) {
              // Éviter les correspondances trop courtes
              directMatches.add(textureIndex[texturePath]!);
              matchScore[textureIndex[texturePath]!] = 80;
              _log('Match partiel: $relativeSoundPath -> $texturePath');
            }
          }
        }

        // Stratégie 2: Matching basé sur les dossiers parents
        // Si le son est dans un sous-dossier spécifique (ex: sounds/block/amethyst/break1.ogg)
        if (directMatches.isEmpty && parentFolder.isNotEmpty) {
          for (final texturePath in textureIndex.keys) {
            final texturePathParts = texturePath.split('/');
            if (texturePathParts.length < 2) continue;

            // Vérifier si le dossier parent du son correspond au type de texture
            final soundType = soundPathParts[0]; // ex: "block"
            final textureType = texturePathParts[0]; // ex: "block"

            if (soundType == textureType) {
              // Vérifier si le dossier parent du son est contenu dans le nom de la texture
              final textureName = path.basenameWithoutExtension(texturePath).toLowerCase();

              if (textureName.contains(parentFolder.toLowerCase()) && parentFolder.length > 3) {
                potentialMatches.add(textureIndex[texturePath]!);
                matchScore[textureIndex[texturePath]!] = 70;
                _log('Match par dossier parent: $relativeSoundPath -> $texturePath');
              }
              // Vérifier si le dossier parent + 'block' est égal au nom de la texture
              else if (textureName == '${parentFolder.toLowerCase()}_block') {
                potentialMatches.add(textureIndex[texturePath]!);
                matchScore[textureIndex[texturePath]!] = 85;
                _log('Match par dossier parent avec suffixe _block: $relativeSoundPath -> $texturePath');
              }
            }
          }
        }

        // Stratégie 3: Recherche par mots-clés dans les chemins
        if (directMatches.isEmpty && potentialMatches.isEmpty) {
          // Extraire les mots-clés significatifs
          final soundKeywords = _extractKeywords(baseNameWithoutAction.isEmpty ? parentFolder : baseNameWithoutAction);

          if (soundKeywords.isNotEmpty) {
            for (final texturePath in textureIndex.keys) {
              final normalizedTexturePath = _normalizeFileName(texturePath);

              for (final keyword in soundKeywords) {
                if (normalizedTexturePath.contains(keyword) && keyword.length > 3) {
                  potentialMatches.add(textureIndex[texturePath]!);
                  // Score basé sur la longueur du mot-clé pour favoriser les matches plus spécifiques
                  matchScore[textureIndex[texturePath]!] = 50 + (keyword.length * 2);
                  _log('Match par mot-clé "$keyword": $relativeSoundPath -> $texturePath');
                  break; // Ne compter qu'une fois chaque texture
                }
              }
            }
          }
        }

        // Combiner les résultats et trier par score
        List<String> allMatches = [
          ...directMatches,
          ...potentialMatches
        ];

        // Éliminer les doublons
        allMatches = allMatches.toSet().toList();

        // Trier par score (du plus élevé au plus bas)
        if (allMatches.isNotEmpty) {
          allMatches.sort((a, b) => (matchScore[b] ?? 0).compareTo(matchScore[a] ?? 0));

          // Limiter aux 3 meilleurs matches
          if (allMatches.length > 3) {
            allMatches = allMatches.sublist(0, 3);
          }

          _log('Matches finaux pour $relativeSoundPath: ${allMatches.length} textures');
          soundToTextures[soundPath] = allMatches;
          matchCount += allMatches.length;
        }
      }

      // Convertir soundToTextures en ResourceMatch pour la compatibilité
      for (final texturePath in textureIndex.values) {
        final matchingSounds = <String>[];

        for (final soundPath in soundToTextures.keys) {
          if (soundToTextures[soundPath]!.contains(texturePath)) {
            matchingSounds.add(soundPath);
          }
        }

        if (matchingSounds.isNotEmpty) {
          matches.add(ResourceMatch(
            texturePath: texturePath,
            soundPaths: matchingSounds,
          ));
        }
      }

      _updateProgress(progress: 1.0, message: "Terminé!", current: 100, total: 100);
      _log('Analyse terminée: ${matches.length} textures avec ${matchCount} associations de sons');

      return matches;
    } catch (e) {
      _log('Erreur lors de la correspondance entre sons et textures: $e');
      _updateProgress(progress: 1.0, message: "Erreur: $e", current: 100, total: 100);
      return [];
    }
  }

  /// Enlève les numéros séquentiels à la fin d'un nom (ex: "break1" -> "break")
  String _removeSequentialNumber(String name) {
    final regex = RegExp(r'(\d+)$');
    return name.replaceAll(regex, '');
  }

  /// Trouve les textures associées aux sons
  Future<Map<String, List<String>>> findTexturesForSounds(String resourcePackPath) async {
    _log("Génération des correspondances son-texture...");

    // Initialiser le résultat
    final Map<String, List<String>> soundToTextures = {};

    try {
      _updateProgress(progress: 0.1, message: "Analyse des fichiers...", current: 10, total: 100);

      // Récupérer tous les sons et textures
      final soundsDir = Directory('$resourcePackPath/assets/minecraft/sounds');
      final texturesDir = Directory('$resourcePackPath/assets/minecraft/textures');

      if (!await soundsDir.exists() || !await texturesDir.exists()) {
        _log("Dossiers de sons ou textures introuvables");
        return {};
      }

      // Récupérer les fichiers de sons
      _updateProgress(progress: 0.3, message: "Indexation des sons...", current: 30, total: 100);
      final List<FileSystemEntity> soundFiles = await _getFilesRecursively(soundsDir, [
        '.ogg'
      ]);

      // Récupérer les fichiers de textures
      _updateProgress(progress: 0.5, message: "Indexation des textures...", current: 50, total: 100);
      final List<FileSystemEntity> textureFiles = await _getFilesRecursively(texturesDir, [
        '.png'
      ]);

      // Créer un index des textures pour faciliter la recherche
      final Map<String, String> textureIndex = {};
      for (final textureFile in textureFiles) {
        final relativePath = path.relative(textureFile.path, from: texturesDir.path).replaceAll('\\', '/');
        textureIndex[relativePath.toLowerCase()] = textureFile.path;
      }

      // Analyser chaque son pour trouver les textures correspondantes
      _updateProgress(progress: 0.6, message: "Association sons-textures...", current: 60, total: 100);

      int totalSounds = soundFiles.length;
      int processedSounds = 0;

      for (final soundFile in soundFiles) {
        processedSounds++;

        if (processedSounds % 20 == 0 || processedSounds == totalSounds) {
          final progress = 0.6 + (0.3 * (processedSounds / totalSounds));
          _updateProgress(progress: progress, message: "Analyse des sons $processedSounds/$totalSounds...", current: processedSounds, total: totalSounds);
        }

        final soundPath = soundFile.path;
        final List<String> matchedTextures = _findTexturesForSound(soundPath, textureIndex, texturesDir.path);

        if (matchedTextures.isNotEmpty) {
          soundToTextures[soundPath] = matchedTextures;
        }
      }

      // Sauvegarder dans le cache pour utilisation future
      try {
        _updateProgress(progress: 0.9, message: "Sauvegarde du cache...", current: 90, total: 100);

        // Convertir en liste de SoundTextureMatch pour sérialisation
        final List<SoundTextureMatch> matches = soundToTextures.entries.map((entry) => SoundTextureMatch(soundPath: entry.key, texturePaths: entry.value)).toList();

        final jsonString = json.encode(matches.map((match) => match.toJson()).toList());
        final cacheFile = File('$resourcePackPath/sound_texture_matches.json');
        await cacheFile.writeAsString(jsonString);

        _log('Correspondances sauvegardées dans le cache: ${cacheFile.path}');
      } catch (e) {
        _log('Erreur lors de la sauvegarde du cache: $e');
      }

      _updateProgress(progress: 1.0, message: "Terminé!", current: 100, total: 100);
      return soundToTextures;
    } catch (e) {
      _log('Erreur lors de la génération des correspondances: $e');
      return {};
    }
  }

  /// Trouve les textures qui correspondent à un son spécifique
  List<String> _findTexturesForSound(String soundPath, Map<String, String> textureIndex, String texturesBasePath) {
    final List<String> result = [];

    try {
      // Obtenir le nom du son sans extension et chemin
      final soundName = path.basenameWithoutExtension(soundPath);
      final soundCategory = path.basename(path.dirname(soundPath));

      // Extraire le type d'action (break, place, etc.) s'il existe
      String? actionType;
      for (final action in _actionTypes) {
        if (soundName.contains(action)) {
          actionType = action;
          break;
        }
      }

      // Base du nom sans l'action et sans numéro séquentiel
      String baseNameWithoutAction = _removeSequentialNumber(soundName);
      if (actionType != null) {
        baseNameWithoutAction = baseNameWithoutAction.replaceAll(actionType, '').trim();
      }

      // Si vide après avoir enlevé l'action, utiliser la catégorie
      if (baseNameWithoutAction.isEmpty) {
        baseNameWithoutAction = soundCategory;
      }

      // Chercher les textures qui pourraient correspondre
      for (final texturePath in textureIndex.keys) {
        final textureName = path.basenameWithoutExtension(texturePath);

        // Correspondance directe
        if (textureName.toLowerCase() == baseNameWithoutAction.toLowerCase()) {
          result.add(textureIndex[texturePath]!);
          continue;
        }

        // Correspondance avec catégorie
        if (texturePath.contains(soundCategory) && textureName.contains(baseNameWithoutAction)) {
          result.add(textureIndex[texturePath]!);
          continue;
        }

        // Correspondance partielle
        if (baseNameWithoutAction.length > 3 && textureName.toLowerCase().contains(baseNameWithoutAction.toLowerCase())) {
          result.add(textureIndex[texturePath]!);
        }
      }
    } catch (e) {
      _log('Erreur lors de la recherche de textures pour $soundPath: $e');
    }

    return result;
  }

  /// Récupère récursivement tous les fichiers d'un dossier avec les extensions spécifiées
  Future<List<FileSystemEntity>> _getFilesRecursively(Directory directory, List<String> extensions) async {
    final List<FileSystemEntity> result = [];

    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        final ext = path.extension(entity.path).toLowerCase();
        if (extensions.contains(ext)) {
          result.add(entity);
        }
      }
    }

    return result;
  }

  /// Normalise un nom de fichier pour faciliter la correspondance
  String _normalizeFileName(String fileName) {
    // Remplacer les séparateurs par des espaces
    var normalized = fileName.replaceAll('\\', ' ').replaceAll('/', ' ');

    // Remplacer les underscores et tirets par des espaces
    normalized = normalized.replaceAll('_', ' ').replaceAll('-', ' ');

    // Convertir en minuscules
    return normalized.toLowerCase();
  }

  /// Extrait les mots-clés significatifs d'un nom de texture
  List<String> _extractKeywords(String textureName) {
    // Diviser le nom en mots
    final words = textureName.split(' ');

    // Filtrer les mots courts et les mots communs non significatifs
    final commonWords = [
      'the',
      'and',
      'of',
      'in',
      'on',
      'at',
      'to',
      'for',
      'with',
      'by'
    ];

    return words.where((word) => word.length > 2 && !commonWords.contains(word)).toList();
  }

  /// Trouve les sons spécifiques à une action pour une texture
  List<String> findActionSoundsForTexture(ResourceMatch match, String action) {
    return match.soundPaths.where((soundPath) {
      final soundName = path.basenameWithoutExtension(soundPath).toLowerCase();
      return soundName.contains(action) || path.dirname(soundPath).toLowerCase().contains(action);
    }).toList();
  }

  /// Invalide le cache des correspondances son-texture
  Future<void> invalidateCache(String resourcePackPath) async {
    final cacheFile = File('$resourcePackPath/sound_texture_matches.json');
    if (await cacheFile.exists()) {
      _log('Suppression du cache pour $resourcePackPath');
      try {
        await cacheFile.delete();
        _log('Cache supprimé avec succès');
      } catch (e) {
        _log('Erreur lors de la suppression du cache: $e');
        rethrow;
      }
    } else {
      _log('Aucun fichier cache trouvé à $resourcePackPath');
    }
  }

  /// Charge les correspondances son-texture depuis le cache ou les génère
  Future<Map<String, List<String>>> loadOrGenerateSoundTextureMatches(String resourcePackPath) async {
    try {
      // Vérifier si le fichier cache existe
      final cacheFile = File('$resourcePackPath/sound_texture_matches.json');

      if (await cacheFile.exists()) {
        _log('Fichier cache trouvé: ${cacheFile.path}');

        try {
          // Charger depuis le cache
          final jsonString = await cacheFile.readAsString();
          final List<dynamic> jsonData = json.decode(jsonString);

          final Map<String, List<String>> result = {};

          for (final item in jsonData) {
            final match = SoundTextureMatch.fromJson(item);
            result[match.soundPath] = match.texturePaths;
          }

          _log('Correspondances chargées depuis le cache: ${result.length} entrées');
          return result;
        } catch (e) {
          _log('Erreur lors de la lecture du cache: $e');
          _log('Régénération des correspondances...');
          // Continuer pour générer à nouveau en cas d'erreur
        }
      }

      // Si le cache n'existe pas ou en cas d'erreur, générer les correspondances
      return findTexturesForSounds(resourcePackPath);
    } catch (e) {
      _log('Erreur lors du chargement/génération des correspondances: $e');
      // Retourner une map vide en cas d'erreur plutôt que de planter
      return {};
    }
  }
}
