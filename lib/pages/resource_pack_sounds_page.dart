import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:minecraft_ressource_pack_editor/widgets/sound_card.dart';
import 'package:minecraft_ressource_pack_editor/widgets/error_message.dart';
import '../services/curseforge_service.dart';
import '../models/sound.dart';
import '../services/audio_service.dart';
import '../services/resource_matcher_service.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class ResourcePackSoundsPage extends StatefulWidget {
  final String instanceName;
  final String resourcePackName;
  final Function? toggleTheme;

  const ResourcePackSoundsPage({
    super.key,
    required this.instanceName,
    required this.resourcePackName,
    this.toggleTheme,
  });

  @override
  State<ResourcePackSoundsPage> createState() => _ResourcePackSoundsPageState();
}

class _ResourcePackSoundsPageState extends State<ResourcePackSoundsPage> {
  late final CurseForgeService _curseForgeService;
  late final AudioService _audioService;
  late final ResourceMatcherService _resourceMatcher;

  List<Sound> _sounds = [];
  bool _isLoading = true;
  String _selectedCategory = '';
  String _extractedPath = '';
  String? _currentError;
  Sound? _currentlyPlayingSound;
  bool _showOnlyWithTextures = false;
  String _searchQuery = '';

  // Map pour stocker les textures associées à chaque son
  Map<String, List<String>> _soundToTextures = {};
  Map<String, bool> _expandedSounds = {};

  // Controller pour le champ de recherche
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _curseForgeService = Provider.of<CurseForgeService>(context, listen: false);
    _audioService = Provider.of<AudioService>(context, listen: false);
    _resourceMatcher = Provider.of<ResourceMatcherService>(context, listen: false);

    // Écouter les changements de progression
    _resourceMatcher.progressController.addListener(_onProgressChanged);
    _extractAndLoadSounds();
  }

  @override
  void dispose() {
    _resourceMatcher.progressController.removeListener(_onProgressChanged);
    _audioService.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Supprime le dossier d'extraction et revient à l'écran précédent
  Future<void> _resetAndGoBack() async {
    try {
      // Arrêter l'audio si en cours de lecture
      _audioService.stop();

      // Supprimer le dossier d'extraction
      if (_extractedPath.isNotEmpty) {
        final extractedDir = Directory(_extractedPath);
        if (await extractedDir.exists()) {
          await extractedDir.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('Erreur lors de la suppression du dossier: $e');
    } finally {
      // Revenir à l'écran précédent
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _onProgressChanged() {
    // Cette méthode est appelée quand la progression change
    // Nous forçons un rebuild pour afficher la progression
    if (mounted) setState(() {});
  }

  Future<void> _extractAndLoadSounds() async {
    setState(() {
      _isLoading = true;
      _currentError = null;
    });

    try {
      // Extraire le resource pack
      await _curseForgeService.extractResourcePack(
        widget.instanceName,
        widget.resourcePackName,
      );

      // Récupérer le chemin d'extraction
      final instancePath = await _curseForgeService.getInstancePath(widget.instanceName);
      _extractedPath = path.join(instancePath, 'extracted', widget.resourcePackName);

      // Charger les sons
      final sounds = await _curseForgeService.getResourcePackSounds(
        widget.instanceName,
        widget.resourcePackName,
      );

      if (sounds.isEmpty) {
        setState(() {
          _currentError = 'Aucun son trouvé dans ce resource pack';
          _isLoading = false;
        });
        return;
      }

      // Charger les associations son -> texture depuis le fichier cache ou les générer si nécessaire
      final soundToTextures = await _resourceMatcher.loadOrGenerateSoundTextureMatches(_extractedPath);

      setState(() {
        _sounds = sounds;
        _soundToTextures = soundToTextures;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${sounds.length} sons chargés ${soundToTextures.isNotEmpty ? "avec ${soundToTextures.length} associations de textures" : ""}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      setState(() {
        _currentError = 'Erreur lors du chargement: $e';
        _isLoading = false;
      });
      debugPrint('Erreur lors du chargement: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _regenerateCache() async {
    setState(() {
      _isLoading = true;
      _currentError = null;
    });

    try {
      // Supprimer le cache existant
      await _resourceMatcher.invalidateCache(_extractedPath);

      // Régénérer les correspondances
      final soundToTextures = await _resourceMatcher.loadOrGenerateSoundTextureMatches(_extractedPath);

      setState(() {
        _soundToTextures = soundToTextures;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cache régénéré avec succès (${soundToTextures.length} associations)'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _currentError = 'Erreur lors de la régénération du cache: $e';
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la régénération du cache: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  List<String> getCategories() {
    return _sounds.map((s) => s.category).toSet().toList()..sort();
  }

  List<Sound> getFilteredSounds() {
    // Première étape: filtrer par catégorie
    var filteredSounds = _selectedCategory.isEmpty ? _sounds : _sounds.where((s) => s.category == _selectedCategory).toList();

    // Deuxième étape: filtrer par textures
    if (_showOnlyWithTextures) {
      filteredSounds = filteredSounds.where((sound) {
        final soundPath = sound.getFullPath(_extractedPath);
        return hasSoundTextures(soundPath);
      }).toList();
    }

    // Troisième étape: filtrer par recherche
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredSounds = filteredSounds.where((sound) {
        final name = sound.name.toLowerCase();
        final path = sound.path.toLowerCase();
        final category = sound.category.toLowerCase();
        return name.contains(query) || path.contains(query) || category.contains(query);
      }).toList();
    }

    return filteredSounds;
  }

  // Normaliser un chemin pour la comparaison
  String _normalizePath(String path) {
    return path.replaceAll('\\', '/').toLowerCase().replaceAll('//', '/');
  }

  // Vérifier si un son a des textures associées
  bool hasSoundTextures(String soundPath) {
    // Si le chemin exact existe, utiliser directement
    if (_soundToTextures.containsKey(soundPath)) {
      return _soundToTextures[soundPath]!.isNotEmpty;
    }

    // Normaliser le chemin donné
    final normalizedInput = _normalizePath(soundPath);

    // Rechercher dans les clés normalisées
    for (final key in _soundToTextures.keys) {
      final normalizedKey = _normalizePath(key);
      if (normalizedKey == normalizedInput || normalizedKey.endsWith(_normalizePath(path.basename(soundPath)))) {
        return _soundToTextures[key]!.isNotEmpty;
      }
    }

    // Essayer de trouver une correspondance partielle dans les clés
    final soundBase = path.basenameWithoutExtension(soundPath).toLowerCase();
    for (final key in _soundToTextures.keys) {
      if (path.basenameWithoutExtension(key).toLowerCase() == soundBase) {
        return _soundToTextures[key]!.isNotEmpty;
      }
    }

    return false;
  }

  // Récupérer toutes les textures associées à un son
  List<String> getTexturesForSound(String soundPath) {
    List<String> result = [];

    // Normaliser le chemin donné
    final normalizedInput = _normalizePath(soundPath);

    // Vérifier différentes manières de faire correspondre les sons
    for (final key in _soundToTextures.keys) {
      final normalizedKey = _normalizePath(key);

      // Correspondance exacte
      if (normalizedKey == normalizedInput) {
        result = _soundToTextures[key]!;
        break;
      }

      // Correspondance par nom de fichier
      if (normalizedKey.endsWith(_normalizePath(path.basename(soundPath)))) {
        result = _soundToTextures[key]!;
        break;
      }

      // Correspondance par nom de base (sans extension)
      final soundBase = path.basenameWithoutExtension(soundPath).toLowerCase();
      if (path.basenameWithoutExtension(key).toLowerCase() == soundBase) {
        result = _soundToTextures[key]!;
        break;
      }
    }

    return result;
  }

  void _playSound(String filePath, Sound sound) {
    try {
      if (_audioService.isPlaying && _currentlyPlayingSound == sound) {
        // Si le même son est en cours de lecture, l'arrêter
        _audioService.stop();
        setState(() {
          _currentlyPlayingSound = null;
        });
      } else {
        // Sinon, jouer le nouveau son
        _audioService.playSound(filePath);
        setState(() {
          _currentlyPlayingSound = sound;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la lecture du son: $e')),
      );
    }
  }

  void _toggleExpand(Sound sound) {
    setState(() {
      final soundId = '${sound.category}/${sound.path}';
      _expandedSounds[soundId] = !(_expandedSounds[soundId] ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = getCategories();
    final filteredSounds = getFilteredSounds();
    final progress = _resourceMatcher.progressController.value;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.resourcePackName),
        actions: [
          IconButton(
            icon: Icon(Theme.of(context).brightness == Brightness.light ? Icons.dark_mode : Icons.light_mode),
            onPressed: () {
              if (widget.toggleTheme != null) widget.toggleTheme!();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Régénérer le cache',
            onPressed: _regenerateCache,
          ),
        ],
      ),
      body: Column(
        children: [
          // Afficher la progression si en cours
          if (progress != null && progress.progress < 1.0)
            LinearProgressIndicator(
              value: progress.progress,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
            ),

          // Barre de recherche (nouveau)
          if (!_isLoading && _currentError == null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Rechercher des sons...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),

          // Sélecteur de catégorie
          if (!_isLoading && _currentError == null)
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('Tous'),
                          selected: _selectedCategory.isEmpty,
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategory = '';
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        ...categories.map((category) => Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: FilterChip(
                                label: Text(category),
                                selected: _selectedCategory == category,
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedCategory = selected ? category : '';
                                  });
                                },
                              ),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilterChip(
                        label: const Text('Textures uniquement'),
                        selected: _showOnlyWithTextures,
                        onSelected: (selected) {
                          setState(() {
                            _showOnlyWithTextures = selected;
                          });
                        },
                      ),
                      const Spacer(),
                      // Afficher le nombre de sons filtrés et le total
                      Text('${filteredSounds.length} sur ${_sounds.length} sons'),
                    ],
                  ),
                ],
              ),
            ),

          // Contenu principal
          Expanded(
            child: _buildContent(filteredSounds),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<Sound> sounds) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_currentError != null) {
      return ErrorMessage(
        message: _currentError!,
        onRetry: _extractAndLoadSounds,
      );
    }

    if (sounds.isEmpty) {
      return const Center(child: Text('Aucun son trouvé'));
    }

    return ListView.builder(
      itemCount: sounds.length,
      itemBuilder: (context, index) {
        final sound = sounds[index];
        final soundFullPath = sound.getFullPath(_extractedPath);
        final fileExists = File(soundFullPath).existsSync();
        final hasTextures = hasSoundTextures(soundFullPath);
        final texturesForSound = getTexturesForSound(soundFullPath);
        final soundId = '${sound.category}/${sound.path}';
        final isExpanded = _expandedSounds[soundId] ?? false;

        return SoundCard(
          sound: sound,
          soundPath: soundFullPath,
          fileExists: fileExists,
          hasTextures: hasTextures,
          texturesForSound: texturesForSound,
          isExpanded: isExpanded,
          currentlyPlayingSound: _currentlyPlayingSound,
          extractedPath: _extractedPath,
          onPlaySound: _playSound,
          onToggleExpand: _toggleExpand,
        );
      },
    );
  }
}
