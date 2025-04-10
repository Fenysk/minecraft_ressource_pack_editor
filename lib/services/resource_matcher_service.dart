import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import '../models/resource_match.dart';

/// Type de callback pour les mises à jour de progression
typedef ProgressCallback = void Function(double progress, String message);

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

  /// Mode debug pour les logs détaillés
  final bool _debugMode = true;

  /// Stream pour suivre la progression
  final progressController = ValueNotifier<MatcherProgress?>(null);

  /// Récupérer les logs
  List<String> get logs => List.unmodifiable(_logs);

  void _log(String message) {
    final logMsg = "${DateTime.now().toIso8601String().substring(11, 19)} - $message";
    _logs.add(logMsg);
    if (kDebugMode) {
      print(logMsg);
    }
  }

  void _logDebug(String message) {
    if (_debugMode) {
      final logMsg = "${DateTime.now().toIso8601String().substring(11, 19)} - DEBUG - $message";
      _logs.add(logMsg);
      if (kDebugMode) {
        print(logMsg);
      }
    }
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
          _updateProgress(progress: progressPercent, message: "Analyse son $processedSounds/$totalSounds...", current: processedSounds, total: totalSounds);
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

  /// Génère les correspondances sons-textures
  Future<Map<String, List<String>>> findTexturesForSounds(String resourcePackPath) async {
    final Map<String, List<String>> soundToTextures = {};

    _log('Démarrage de la génération des correspondances pour $resourcePackPath');

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
        final List<String> matchedTextures = _findTexturesForSound(soundPath, textureIndex.values.toList());

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

  /// Trouve les textures correspondant à un son spécifique
  List<String> _findTexturesForSound(String soundPath, List<String> texturePaths) {
    final List<String> matchResults = [];
    final textureScores = <String, int>{};

    // Extraire des informations sur le son pour le matching
    final soundName = path.basenameWithoutExtension(soundPath).toLowerCase();
    final soundDir = path.dirname(soundPath).toLowerCase();
    final soundPathParts = soundPath.split('/');

    // Extraire le type de son (block, ambient, etc.)
    String soundType = '';
    if (soundPathParts.isNotEmpty) {
      for (int i = 0; i < soundPathParts.length; i++) {
        if (soundPathParts[i] == 'sounds' && i + 1 < soundPathParts.length) {
          soundType = soundPathParts[i + 1];
          break;
        }
      }
    }

    _logDebug('\n--- ANALYSE POUR SON: $soundPath ---');
    _logDebug('  Nom: $soundName');
    _logDebug('  Dossier: $soundDir');
    _logDebug('  Type son: $soundType');

    // Déterminer le type d'action du son (déterminé par le nom ou le contexte)
    String actionType = '';
    if (soundName.contains('break')) {
      actionType = 'break';
    } else if (soundName.contains('place') || soundName.contains('set')) {
      actionType = 'place';
    } else if (soundName.contains('step') || soundName.contains('walk')) {
      actionType = 'step';
    } else if (soundName.contains('hit')) {
      actionType = 'hit';
    }

    _logDebug('  Action: $actionType');

    // Déterminer le contexte matériel
    String materialContext = '';
    String baseMaterial = '';

    // Liste des contextes génériques (pas des matériaux)
    final genericContexts = [
      'block',
      'ambient',
      'item',
      'entity',
      'sounds',
      'music',
      'sound'
    ];

    // Extraction depuis le chemin du son
    // Exemple: sounds/block/stone/break.ogg -> stone est le matériau
    List<String> soundParts = soundPath.toLowerCase().split(RegExp(r'[/\\]'));
    for (int i = 0; i < soundParts.length - 1; i++) {
      if (soundParts[i] == 'sounds' && i + 1 < soundParts.length) {
        // Ignorer les catégories générales
        if (i + 2 < soundParts.length && genericContexts.contains(soundParts[i + 1])) {
          materialContext = soundParts[i + 2];
          _logDebug('  Contexte matériel (sous-dossier): $materialContext');
        } else if (!genericContexts.contains(soundParts[i + 1])) {
          materialContext = soundParts[i + 1];
          _logDebug('  Contexte matériel (dossier): $materialContext');
        }
        break;
      }
    }

    // Extraction depuis le nom du fichier (si pas trouvé dans le chemin ou si c'est un contexte générique)
    if (materialContext.isEmpty || genericContexts.contains(materialContext)) {
      // Cas spéciaux pour une meilleure détection des matériaux
      if (soundName.contains('wood_') || soundName.contains('_wood')) {
        materialContext = 'wood';
        _logDebug('  Contexte matériel (nom - cas spécial): $materialContext');
      } else if (soundName.contains('stone_') || soundName.contains('_stone')) {
        materialContext = 'stone';
        _logDebug('  Contexte matériel (nom - cas spécial): $materialContext');
      } else {
        // Recherche basique de matériau dans le nom
        for (final material in [
          'wood',
          'stone',
          'grass',
          'dirt',
          'gravel',
          'sand',
          'wool',
          'metal',
          'glass',
          'bone',
          'netherrack',
          'soul_sand',
          'amethyst',
          'bamboo'
        ]) {
          if (soundName.contains(material)) {
            materialContext = material;
            _logDebug('  Contexte matériel (nom): $materialContext');
            break;
          }
        }
      }
    }

    // Si toujours pas de contexte matériel, essayer une dernière approche avec le nom du fichier
    if (materialContext.isEmpty) {
      // Enlever les suffixes numériques et d'action du nom
      String cleanName = soundName.replaceAll(RegExp(r'\d+$'), '');
      for (final action in [
        'break',
        'step',
        'hit',
        'place'
      ]) {
        cleanName = cleanName.replaceAll(action, '');
      }
      cleanName = cleanName.replaceAll(RegExp(r'[_\s-]+'), ' ').trim();

      if (cleanName.isNotEmpty && !genericContexts.contains(cleanName)) {
        materialContext = cleanName;
        _logDebug('  Contexte matériel (nom nettoyé): $materialContext');
      }
    }

    // Simplifier le contexte matériel pour la recherche
    baseMaterial = materialContext.replaceAll('_block', '').replaceAll('_planks', '');
    if (baseMaterial.isEmpty) baseMaterial = materialContext;

    _logDebug('  Matériau de base: $baseMaterial');

    // Si aucun matériau pertinent n'a été trouvé, on utilise une approche plus permissive
    if (baseMaterial.isEmpty || genericContexts.contains(baseMaterial)) {
      _logDebug('  !!! AUCUN MATÉRIAU SPÉCIFIQUE TROUVÉ - UTILISATION D\'UNE APPROCHE GÉNÉRIQUE');

      // Au lieu d'arrêter la recherche, on va chercher des textures correspondant au type de son
      if (soundType.isNotEmpty && !genericContexts.contains(soundType)) {
        baseMaterial = soundType;
        materialContext = soundType;
        _logDebug('  Utilisation du type de son comme contexte: $soundType');
      } else {
        // Utiliser le nom du son complet sans extension comme dernière tentative
        String cleanName = soundName;
        for (final generic in genericContexts) {
          if (cleanName.contains(generic)) {
            cleanName = cleanName.replaceAll(generic, '');
          }
        }
        cleanName = cleanName.replaceAll(RegExp(r'[_\s-]+'), ' ').trim();

        if (cleanName.isNotEmpty) {
          baseMaterial = cleanName;
          materialContext = cleanName;
          _logDebug('  Utilisation du nom nettoyé: $cleanName');
        } else {
          _logDebug('  !!! IMPOSSIBLE DE TROUVER UN CONTEXTE - UTILISATION DU NOM BRUT');
          baseMaterial = soundName;
          materialContext = soundName;
        }
      }
    }

    // Pour le débogage, afficher la tentative de recherche
    _log('Recherche de textures pour le son: $soundPath');
    _log('  → Contexte matériel: $materialContext');
    _log('  → Matériau de base: $baseMaterial');
    _log('  → Type d\'action: $actionType');

    // Vérifier si le matériau appartient à un groupe
    String? materialGroup;
    final materialGroups = _getMaterialGroups();
    for (final group in materialGroups.keys) {
      if (materialGroups[group]!.any((m) => baseMaterial.contains(m))) {
        materialGroup = group;
        _logDebug('  Groupe de matériau: $materialGroup');
        break;
      }
    }

    // Suppression des interdictions spécifiques pour utiliser un système plus général

    // Pour éviter de recalculer les parties de chemins à chaque itération
    final Set<String> precomputedBasenames = {};
    for (final texturePath in texturePaths) {
      precomputedBasenames.add(path.basenameWithoutExtension(texturePath).toLowerCase());
    }

    // Ensemble de textures à traiter immédiatement car excellent match
    final Set<String> fastMatchTextures = {};
    // Si on a un contexte matériel précis
    if (materialContext.isNotEmpty) {
      for (int i = 0; i < texturePaths.length; i++) {
        final texturePath = texturePaths[i];
        final textureName = precomputedBasenames.elementAt(i);

        // Prioritiser les correspondances exactes pour traitement immédiat
        if (textureName == materialContext || textureName == '${materialContext}_block' || textureName == baseMaterial || textureName == '${baseMaterial}_block') {
          fastMatchTextures.add(texturePath);
        }
      }
    }

    // Si des correspondances exactes sont trouvées, on peut retourner immédiatement
    if (fastMatchTextures.isNotEmpty && actionType != 'step') {
      _logDebug('  CORRESPONDANCES EXACTES TROUVÉES - OPTIMISATION RAPIDE');
      final result = fastMatchTextures.take(3).toList();
      return result;
    }

    // Tracker pour les correspondances exactes de matériau
    bool foundExactMaterial = false;

    // Traiter chaque texture
    for (final texturePath in texturePaths) {
      final textureName = path.basenameWithoutExtension(texturePath).toLowerCase();

      // Extraction du chemin pour analyse structurelle
      final texturePathParts = texturePath.split('/');
      final textureType = texturePathParts.isNotEmpty ? texturePathParts[0] : '';

      // Vérifications rapides de filtrage
      if (baseMaterial.isNotEmpty && materialGroup != null) {
        // Extraire le groupe potentiel de la texture
        String? textureGroup;
        for (final group in materialGroups.keys) {
          if (materialGroups[group]!.any((m) => textureName.contains(m) && m.length > 2)) {
            textureGroup = group;
            break;
          }
        }

        // Si la texture a un groupe de matériaux qui est différent du son, c'est probablement un mauvais match
        if (textureGroup != null && textureGroup != materialGroup) {
          // Certains groupes sont compatibles entre eux (par exemple bois et plantes)
          bool compatibleGroups = false;
          if ((materialGroup == 'bois' && textureGroup == 'plantes') || (materialGroup == 'plantes' && textureGroup == 'bois')) {
            compatibleGroups = true;
          }

          if (!compatibleGroups) {
            continue; // Sauter cette texture si groupes incompatibles
          }
        }
      }

      // Initialiser le score à 0
      int score = 0;

      // ===== CORRESPONDANCE AVEC MATÉRIAU =====

      // Tests par ordre de rapidité d'exécution (du plus rapide au plus lent)

      // 1. Correspondance exacte (la plus rapide)
      if (textureName == materialContext) {
        score += 2000;
        foundExactMaterial = true;
        _logDebug('  - MATCH EXACT: $texturePath (+2000)');
      } else if (textureName == '${materialContext}_block') {
        score += 1900;
        foundExactMaterial = true;
        _logDebug('  - MATCH BLOCK: $texturePath (+1900)');
      } else if (textureName == baseMaterial) {
        score += 1000;
        foundExactMaterial = true;
        _logDebug('  - MATCH BASE: $texturePath (+1000)');
      } else if (textureName == '${baseMaterial}_block') {
        score += 900;
        foundExactMaterial = true;
        _logDebug('  - MATCH BASE BLOCK: $texturePath (+900)');
      }
      // 2. Contient le matériau
      else if (baseMaterial.length > 2) {
        if (textureName.contains(materialContext)) {
          // Vérification de mot entier seulement si nécessaire
          if (_isWholeWord(textureName, materialContext)) {
            score += 1500;
            foundExactMaterial = true;
            _logDebug('  - MATCH MOT ENTIER: $texturePath (+1500)');
          } else {
            score += 700;
            foundExactMaterial = true;
            _logDebug('  - CONTIENT MATÉRIAU: $texturePath (+700)');
          }
        } else if (textureName.contains(baseMaterial)) {
          // Vérification de mot entier seulement si nécessaire
          if (_isWholeWord(textureName, baseMaterial)) {
            score += 800;
            foundExactMaterial = true;
            _logDebug('  - MATCH BASE MOT ENTIER: $texturePath (+800)');
          } else {
            score += 500;
            foundExactMaterial = true;
            _logDebug('  - CONTIENT BASE: $texturePath (+500)');
          }
        }
      }

      // Bonus pour le chemin (test simple)
      if (texturePath.contains('/$baseMaterial/')) {
        score += 200;
        foundExactMaterial = true;
      }

      // Si aucune correspondance de base trouvée, passer à la texture suivante
      if (score == 0) {
        // Au lieu de sauter, assigner un score minimal pour encourager les correspondances
        score = 50;
      }

      // ===== BONUS CONTEXTUELS =====

      // Ces bonus sont appliqués seulement aux candidats valides

      // 1. Bonus par type d'action
      if (actionType.isNotEmpty) {
        if (actionType == 'step' && (textureName.contains('_top') || textureName.contains('_planks'))) {
          score += 300;
        } else if (actionType == 'break' && !textureName.contains('_top') && !textureName.contains('_side')) {
          score += 200;
        } else if (actionType == 'place' && !textureName.contains('_top') && !textureName.contains('_bottom')) {
          score += 200;
        }
      }

      // 2. Bonus de structure (test simple)
      if (soundType == textureType) {
        score += 150;

        // Bonus supplémentaire si les deux niveaux correspondent
        if (soundPathParts.length > 1 && texturePathParts.length > 1 && soundPathParts[1] == texturePathParts[1]) {
          score += 200;
        }
      }

      // 3. Bonus de groupe sémantique
      if (materialGroup != null) {
        // Vérification par groupe sémantique
        bool sameGroup = false;
        final groupMaterials = materialGroups[materialGroup]!;

        // Utiliser une vérification par ensemble plutôt qu'une boucle
        for (final material in groupMaterials) {
          if (material.length > 2 && textureName.contains(material)) {
            sameGroup = true;
            break;
          }
        }

        if (sameGroup) {
          score += 250;
        }
      }

      // 4. Bonus de similarité (coûteux - appliquer seulement aux candidats prometteurs)
      if (score > 500 && baseMaterial.length > 2) {
        double similarity = _computeQuickSimilarity(baseMaterial, textureName);
        if (similarity > 0.6) {
          int similarityBonus = (similarity * 300).round();
          score += similarityBonus;
        }
      }

      // 5. Bonus spécifiques (cas particuliers)
      if (materialContext == 'bamboo_wood') {
        if (textureName.contains('bamboo_') && (textureName.contains('_planks') || textureName.contains('_block'))) {
          score += 1000;
        }
      }

      // 6. Traitement pour les sons sans contexte matériel clair
      // Si le score est faible mais que la texture semble pertinente par contexte d'action
      if (score < 200 && actionType.isNotEmpty && textureName.contains(actionType)) {
        score += 150;
        _logDebug('  - BONUS ACTION: $texturePath (+150)');
      }

      // 7. Correspondance par mots-clés individuels
      // Si le score est encore faible, essayer de trouver des mots-clés communs
      if (score < 100) {
        // Extraire les mots-clés du matériau et de la texture
        final materialWords = materialContext.split(RegExp(r'[_\s-]+')).where((w) => w.length > 2).toSet();
        final textureWords = textureName.split(RegExp(r'[_\s-]+')).where((w) => w.length > 2).toSet();

        // Trouver les mots-clés communs
        final commonWords = materialWords.intersection(textureWords);

        if (commonWords.isNotEmpty) {
          score += 50 * commonWords.length;
          _logDebug('  - MOTS-CLÉS COMMUNS: $texturePath (${commonWords.toList()}, +${50 * commonWords.length})');
        }
      }

      // Ajouter à la liste des résultats seulement si le score est suffisant
      // Score minimum réduit pour augmenter les chances de correspondance
      if (score >= 50) {
        textureScores[texturePath] = score;
      }
    }

    // Si aucune texture pertinente trouvée
    if (textureScores.isEmpty) {
      _logDebug('  !!! AUCUNE TEXTURE PERTINENTE TROUVÉE - MÉTHODE DE SECOURS');

      // Dernière tentative: si nous n'avons trouvé aucune correspondance, prendre les textures
      // qui contiennent simplement une partie du nom du son (méthode de secours)
      final backupScores = <String, int>{};

      for (final texturePath in texturePaths) {
        final textureName = path.basenameWithoutExtension(texturePath).toLowerCase();

        // Vérifier si le nom de la texture contient au moins 3 caractères consécutifs du nom du son
        for (int i = 0; i <= soundName.length - 3; i++) {
          final subString = soundName.substring(i, i + 3);
          if (subString.length >= 3 && textureName.contains(subString)) {
            int backupScore = 100 + (subString.length * 5);
            backupScores[texturePath] = backupScore;
            _logDebug('  - CORRESPONDANCE DE SECOURS: $texturePath (sous-chaîne: $subString, +$backupScore)');
            break;
          }
        }
      }

      // Si on a trouvé des correspondances de secours, utiliser celles-ci
      if (backupScores.isNotEmpty) {
        textureScores.addAll(backupScores);
        _logDebug('  - ${backupScores.length} CORRESPONDANCES DE SECOURS TROUVÉES');
      }
    }

    // Si toujours aucune texture pertinente trouvée
    if (textureScores.isEmpty) {
      _logDebug('  !!! ÉCHEC DE TOUTES LES MÉTHODES - AUCUNE CORRESPONDANCE');
      return [];
    }

    // Trier et limiter aux meilleurs résultats
    final sortedTextures = textureScores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // Prendre les 3 meilleures textures maximum
    final int maxResults = 3;
    final int resultCount = sortedTextures.length > maxResults ? maxResults : sortedTextures.length;

    for (var i = 0; i < resultCount; i++) {
      matchResults.add(sortedTextures[i].key);
      _logDebug('  - RÉSULTAT #${i + 1}: ${path.basename(sortedTextures[i].key)} (score: ${sortedTextures[i].value})');
    }

    return matchResults;
  }

  /// Méthode optimisée pour calculer une similarité rapide entre deux chaînes
  double _computeQuickSimilarity(String a, String b) {
    // Cas triviaux
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    // Utiliser des ensembles de caractères pour une comparaison rapide
    final setA = a.split('').toSet();
    final setB = b.split('').toSet();

    // Coefficient de Jaccard: intersection / union
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;

    return intersection / union;
  }

  /// Vérifie si search est un mot entier dans text
  bool _isWholeWord(String text, String search) {
    // Optimisation: vérifier d'abord si le texte contient la recherche
    if (!text.contains(search)) return false;

    // Utiliser une expression régulière avec des limites de mots
    final regexp = RegExp(r'\b' + search + r'\b');
    return regexp.hasMatch(text);
  }

  /// Cache des groupes de matériaux (évite de recréer à chaque appel)
  Map<String, List<String>> _getMaterialGroups() {
    return {
      'bois': [
        'oak',
        'spruce',
        'birch',
        'jungle',
        'acacia',
        'dark_oak',
        'mangrove',
        'bamboo',
        'cherry',
        'wood',
        'planks',
        'log'
      ],
      'pierre': [
        'stone',
        'cobblestone',
        'granite',
        'diorite',
        'andesite',
        'deepslate',
        'tuff',
        'basalt',
        'blackstone',
        'calcite'
      ],
      'métaux': [
        'iron',
        'gold',
        'copper',
        'netherite',
        'chain',
        'metal'
      ],
      'cristaux': [
        'amethyst',
        'crystal',
        'glass',
        'diamond',
        'emerald',
        'quartz'
      ],
      'terre': [
        'dirt',
        'grass',
        'mud',
        'clay',
        'soul',
        'sand',
        'gravel',
        'soil'
      ],
      'plantes': [
        'leaves',
        'azalea',
        'vine',
        'moss',
        'flower',
        'root',
        'sapling',
        'spore',
        'fungus',
        'wart'
      ],
    };
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

  /// Invalide le cache des correspondances son-texture et supprime tout fichier cache
  Future<void> invalidateCache(String resourcePackPath) async {
    try {
      // Supprimer le fichier de cache
      final cacheFile = File('$resourcePackPath/sound_texture_matches.json');
      if (await cacheFile.exists()) {
        _log('Suppression du fichier cache...');
        await cacheFile.delete();
      }

      // Supprimer tout autre fichier de cache potentiel
      final cacheDir = Directory(resourcePackPath);
      final entities = await cacheDir.list().toList();

      for (final entity in entities) {
        if (entity is File && (entity.path.endsWith('.cache') || entity.path.contains('cache') || entity.path.endsWith('.json'))) {
          _log('Suppression du fichier cache supplémentaire: ${entity.path}');
          await entity.delete();
        }
      }

      _log('Cache nettoyé avec succès');
    } catch (e) {
      _log('Erreur lors du nettoyage du cache: $e');
      rethrow;
    }
  }

  /// Charge ou génère les correspondances son-texture
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

          // SUPPRESSION EXPLICITE DES ASSOCIATIONS INCORRECTES
          _log('Vérification des associations incorrectes...');
          final result2 = await _removeInvalidAssociations(result, resourcePackPath);

          _log('Correspondances chargées et vérifiées: ${result2.length} entrées');
          return result2;
        } catch (e) {
          _log('Erreur lors de la lecture du cache: $e');
          _log('Régénération des correspondances...');
          // Continuer pour générer à nouveau en cas d'erreur
        }
      }

      // Si le cache n'existe pas ou en cas d'erreur, générer les correspondances
      _log('Génération des correspondances depuis zéro...');
      return findTexturesForSounds(resourcePackPath);
    } catch (e) {
      _log('Erreur lors du chargement/génération des correspondances: $e');
      // Retourner une map vide en cas d'erreur plutôt que de planter
      return {};
    }
  }

  /// Supprime les associations incorrectes selon des règles strictes
  Future<Map<String, List<String>>> _removeInvalidAssociations(Map<String, List<String>> associations, String resourcePackPath) async {
    final Map<String, List<String>> cleanedAssociations = {};

    // Vérifier chaque association
    int totalInvalid = 0;
    final materialGroups = _getMaterialGroups();

    for (final soundPath in associations.keys) {
      final texturesList = associations[soundPath] ?? [];

      // Obtenir le matériau à partir du chemin du son
      final soundDir = path.dirname(soundPath);
      final materialContext = path.basename(soundDir).toLowerCase();

      // Extraire le matériau de base pour les matériaux composés (ex: bamboo_wood -> bamboo)
      final baseMaterial = materialContext.split('_').first;

      // Déterminer le groupe du son
      String? soundGroup;
      for (final group in materialGroups.keys) {
        if (materialGroups[group]!.any((m) => baseMaterial.contains(m) || materialContext.contains(m))) {
          soundGroup = group;
          break;
        }
      }

      // Liste des textures valides pour ce son
      final validTextures = <String>[];

      // Vérifier chaque texture
      for (final texturePath in texturesList) {
        final textureName = path.basenameWithoutExtension(texturePath).toLowerCase();
        bool isValid = true;

        // 1. Vérifier si la texture appartient à un groupe incompatible
        if (soundGroup != null) {
          // Déterminer le groupe de la texture
          String? textureGroup;
          for (final group in materialGroups.keys) {
            if (materialGroups[group]!.any((m) => textureName.contains(m) && m.length > 2)) {
              textureGroup = group;
              break;
            }
          }

          // Si la texture a un groupe différent du son et non compatible
          if (textureGroup != null && textureGroup != soundGroup) {
            // Certains groupes sont compatibles entre eux
            bool compatibleGroups = false;
            if ((soundGroup == 'bois' && textureGroup == 'plantes') || (soundGroup == 'plantes' && textureGroup == 'bois')) {
              compatibleGroups = true;
            }

            if (!compatibleGroups) {
              isValid = false;
              totalInvalid++;
              _log('SUPPRESSION: Association incorrecte entre $soundPath et $texturePath (groupe incompatible: $textureGroup vs $soundGroup)');
            }
          }
        }

        // 2. Vérification supplémentaire: la texture doit contenir une partie du matériau
        if (isValid) {
          bool hasRelevance = textureName.contains(baseMaterial);

          if (!hasRelevance && materialContext.contains('_')) {
            // Vérifier les parties du matériau composé
            final parts = materialContext.split('_');
            for (final part in parts) {
              if (part.length > 2 && textureName.contains(part)) {
                hasRelevance = true;
                break;
              }
            }
          }

          if (!hasRelevance) {
            isValid = false;
            totalInvalid++;
            _log('SUPPRESSION: Texture non pertinente pour $soundPath: $texturePath (ne contient pas $baseMaterial)');
          }
        }

        // Si valide, ajouter à la liste
        if (isValid) {
          validTextures.add(texturePath);
        }
      }

      // Ajouter l'association nettoyée si des textures valides existent
      if (validTextures.isNotEmpty) {
        cleanedAssociations[soundPath] = validTextures;
      }
    }

    _log('Nettoyage terminé: $totalInvalid associations incorrectes supprimées');

    // Enregistrer les associations nettoyées dans le cache
    await _saveMatchesToCache(cleanedAssociations, resourcePackPath);

    return cleanedAssociations;
  }

  /// Sauvegarde les correspondances dans le fichier cache
  Future<void> _saveMatchesToCache(Map<String, List<String>> matches, String resourcePackPath) async {
    try {
      final cacheFile = File('$resourcePackPath/sound_texture_matches.json');

      // Convertir les correspondances en liste de SoundTextureMatch pour la sérialisation
      final List<SoundTextureMatch> matchesList = [];

      for (final entry in matches.entries) {
        matchesList.add(SoundTextureMatch(
          soundPath: entry.key,
          texturePaths: entry.value,
        ));
      }

      // Convertir en JSON
      final jsonData = matchesList.map((m) => m.toJson()).toList();
      final jsonString = json.encode(jsonData);

      // Écrire dans le fichier
      await cacheFile.writeAsString(jsonString);

      _log('Cache sauvegardé avec succès: ${matches.length} entrées');
    } catch (e) {
      _log('Erreur lors de la sauvegarde du cache: $e');
    }
  }
}
