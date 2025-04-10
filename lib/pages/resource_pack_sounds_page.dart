import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:minecraft_ressource_pack_editor/widgets/sound_card.dart';
import '../services/curseforge_service.dart';
import '../models/sound.dart';
import '../services/audio_service.dart';
import '../services/resource_matcher_service.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'dart:async';

class ResourcePackSoundsPage extends StatefulWidget {
  final String instanceName;
  final String resourcePackName;
  final Function? toggleTheme;
  final String extractedPath;

  const ResourcePackSoundsPage({
    super.key,
    required this.instanceName,
    required this.resourcePackName,
    this.toggleTheme,
    required this.extractedPath,
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

  // Pagination
  static const int _pageSize = 50;
  int _currentPage = 0;
  List<Sound> _paginatedSounds = [];
  bool _hasMoreItems = true;
  final ScrollController _scrollController = ScrollController();

  // Map pour stocker les textures associées à chaque son
  Map<String, List<String>> _soundToTextures = {};
  Map<String, bool> _expandedSounds = {};

  // Mise en cache des résultats filtrés
  List<Sound>? _cachedFilteredSounds;
  String? _cachedSearchQuery;
  String? _cachedSelectedCategory;
  bool? _cachedShowOnlyWithTextures;

  // Cache pour les résultats de hasSoundTextures
  final Map<String, bool> _soundTextureCache = {};

  // Controller pour le champ de recherche
  final TextEditingController _searchController = TextEditingController();

  // Délai pour éviter trop de rafraîchissements pendant la frappe
  Timer? _searchDebounce;

  String _loadingMessage = '';

  @override
  void initState() {
    super.initState();
    _curseForgeService = Provider.of<CurseForgeService>(context, listen: false);
    _audioService = Provider.of<AudioService>(context, listen: false);
    _resourceMatcher = Provider.of<ResourceMatcherService>(context, listen: false);

    // Écouter les changements de progression
    _resourceMatcher.progressController.addListener(_onProgressChanged);

    // Écouter le défilement pour charger plus d'éléments
    _scrollController.addListener(_onScroll);

    _extractedPath = widget.extractedPath;
    _currentError = null;

    // Récupérer les correspondances textures-sons
    _extractAndLoadSounds();
  }

  @override
  void dispose() {
    _resourceMatcher.progressController.removeListener(_onProgressChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _audioService.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel(); // Annuler le timer s'il existe
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8 && !_isLoading && _hasMoreItems) {
      _loadMoreItems();
    }
  }

  Future<void> _loadMoreItems() async {
    if (!_hasMoreItems || _isLoading) return;

    setState(() {
      _isLoading = true;
    });

    // Simuler un chargement asynchrone pour améliorer l'UX
    await Future.delayed(const Duration(milliseconds: 200));

    final filteredSounds = getFilteredSounds();
    final startIndex = _currentPage * _pageSize;

    if (startIndex >= filteredSounds.length) {
      setState(() {
        _hasMoreItems = false;
        _isLoading = false;
      });
      return;
    }

    final endIndex = (startIndex + _pageSize < filteredSounds.length) ? startIndex + _pageSize : filteredSounds.length;

    final nextItems = filteredSounds.sublist(startIndex, endIndex);

    setState(() {
      _paginatedSounds.addAll(nextItems);
      _currentPage++;
      _isLoading = false;
      _hasMoreItems = endIndex < filteredSounds.length;
    });
  }

  void _resetPagination() {
    _currentPage = 0;
    _paginatedSounds = [];
    _hasMoreItems = true;

    // Charge la première page immédiatement
    _loadMoreItems();
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
      // Effacer les caches
      _cachedFilteredSounds = null;
      _soundTextureCache.clear();
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
        // Réinitialiser pour le lazy loading
        _resetPagination();
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

  /// Régénère complètement le cache des associations texture-son
  Future<void> _regenerateCache() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Préparation du nettoyage du cache...';
    });

    try {
      // Étape 1: Vider tous les caches en mémoire
      _soundTextureCache.clear();
      _texturesForSoundCache.clear();
      _cachedFilteredSounds = null;

      // Étape 2: Forcer la suppression de tous les fichiers de cache sur disque
      _loadingMessage = 'Suppression des fichiers cache...';
      setState(() {});
      await _resourceMatcher.invalidateCache(_extractedPath);

      // Étape 3: Courte pause pour s'assurer que les fichiers sont bien supprimés
      await Future.delayed(const Duration(milliseconds: 500));

      // Étape 4: Régénérer les associations depuis zéro
      _loadingMessage = 'Recalcul des associations son-texture...';
      setState(() {});
      final newMatches = await _resourceMatcher.loadOrGenerateSoundTextureMatches(_extractedPath);

      setState(() {
        _soundToTextures = newMatches;
        _isLoading = false;
        _loadingMessage = '';
      });

      // Notification de réussite
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Associations recalculées avec succès. Les résultats incorrects ont été supprimés.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );

      // Recharger la pagination pour montrer les nouvelles associations
      _resetPagination();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _loadingMessage = '';
      });

      // Notification d'erreur
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la régénération: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<String> getCategories() {
    return _sounds.map((s) => s.category).toSet().toList()..sort();
  }

  List<Sound> getFilteredSounds() {
    // Vérifier si les paramètres de filtrage ont changé
    if (_cachedFilteredSounds != null && _cachedSearchQuery == _searchQuery && _cachedSelectedCategory == _selectedCategory && _cachedShowOnlyWithTextures == _showOnlyWithTextures) {
      return _cachedFilteredSounds!;
    }

    // Si les paramètres ont changé, filtrer à nouveau

    // Première étape: filtrer par catégorie (le plus rapide)
    var filteredSounds = _selectedCategory.isEmpty ? _sounds : _sounds.where((s) => s.category == _selectedCategory).toList();

    // Deuxième étape: filtrer par recherche (assez rapide)
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredSounds = filteredSounds.where((sound) {
        final name = sound.name.toLowerCase();
        final path = sound.path.toLowerCase();
        final category = sound.category.toLowerCase();
        return name.contains(query) || path.contains(query) || category.contains(query);
      }).toList();
    }

    // Troisième étape: filtrer par textures (plus coûteuse, faire en dernier)
    if (_showOnlyWithTextures) {
      filteredSounds = filteredSounds.where((sound) {
        final soundPath = sound.getFullPath(_extractedPath);
        return hasSoundTextures(soundPath);
      }).toList();
    }

    // Mettre en cache les résultats
    _cachedFilteredSounds = filteredSounds;
    _cachedSearchQuery = _searchQuery;
    _cachedSelectedCategory = _selectedCategory;
    _cachedShowOnlyWithTextures = _showOnlyWithTextures;

    // Réinitialiser la pagination quand les filtres changent
    return filteredSounds;
  }

  // Normaliser un chemin pour la comparaison
  String _normalizePath(String path) {
    return path.replaceAll('\\', '/').toLowerCase().replaceAll('//', '/');
  }

  // Vérifier si un son a des textures associées
  bool hasSoundTextures(String soundPath) {
    // Vérifier le cache d'abord
    if (_soundTextureCache.containsKey(soundPath)) {
      return _soundTextureCache[soundPath]!;
    }

    bool result;

    // Si le chemin exact existe, utiliser directement
    if (_soundToTextures.containsKey(soundPath)) {
      result = _soundToTextures[soundPath]!.isNotEmpty;
      _soundTextureCache[soundPath] = result;
      return result;
    }

    // Normaliser le chemin donné
    final normalizedInput = _normalizePath(soundPath);

    // Rechercher dans les clés normalisées
    for (final key in _soundToTextures.keys) {
      final normalizedKey = _normalizePath(key);
      if (normalizedKey == normalizedInput || normalizedKey.endsWith(_normalizePath(path.basename(soundPath)))) {
        result = _soundToTextures[key]!.isNotEmpty;
        _soundTextureCache[soundPath] = result;
        return result;
      }
    }

    // Essayer de trouver une correspondance partielle dans les clés
    final soundBase = path.basenameWithoutExtension(soundPath).toLowerCase();
    for (final key in _soundToTextures.keys) {
      if (path.basenameWithoutExtension(key).toLowerCase() == soundBase) {
        result = _soundToTextures[key]!.isNotEmpty;
        _soundTextureCache[soundPath] = result;
        return result;
      }
    }

    _soundTextureCache[soundPath] = false;
    return false;
  }

  // Récupérer toutes les textures associées à un son avec mise en cache
  final Map<String, List<String>> _texturesForSoundCache = {};

  List<String> getTexturesForSound(String soundPath) {
    // Vérifier le cache d'abord
    if (_texturesForSoundCache.containsKey(soundPath)) {
      return _texturesForSoundCache[soundPath]!;
    }

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

    // Mettre en cache le résultat
    _texturesForSoundCache[soundPath] = result;
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

  void _handleSearch(String value) {
    // Mettre à jour la valeur de recherche sans déclencher de rechargement immédiat
    setState(() {
      _searchQuery = value;
      // Réinitialiser le cache des résultats filtrés seulement
      _cachedFilteredSounds = null;
    });

    // Utiliser un délai pour éviter de recharger trop fréquemment pendant la frappe
    _debounceSearch();
  }

  void _debounceSearch() {
    // Annuler le timer précédent s'il existe
    if (_searchDebounce?.isActive ?? false) {
      _searchDebounce!.cancel();
    }

    // Définir un nouveau timer
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      // Appliquer le filtrage et recharger les données après le délai
      if (mounted) {
        _resetPagination();
      }
    });
  }

  void _handleCategoryChange(String? category) {
    setState(() {
      _selectedCategory = category ?? '';
      _cachedFilteredSounds = null;
      _resetPagination();
    });
  }

  void _handleTexturesFilterChange(bool selected) {
    setState(() {
      _showOnlyWithTextures = selected;
      _cachedFilteredSounds = null;
      _resetPagination();
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = getCategories();
    final allFilteredSounds = getFilteredSounds();
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
          // Menu de débug et options avancées
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Options avancées',
            onSelected: (value) {
              switch (value) {
                case 'clear_cache':
                  _regenerateCache();
                  break;
                case 'clear_files':
                  _showConfirmDialog(
                    'Supprimer les fichiers extraits',
                    'Voulez-vous supprimer les fichiers extraits et revenir à la liste des packs?',
                    () => _resetAndGoBack(),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'clear_cache',
                child: ListTile(
                  leading: Icon(Icons.delete_sweep),
                  title: Text('Forcer une nouvelle analyse'),
                  subtitle: Text('Recalculer toutes les correspondances'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'clear_files',
                child: ListTile(
                  leading: Icon(Icons.delete_forever),
                  title: Text('Supprimer les fichiers'),
                  subtitle: Text('Effacer le dossier extrait'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _loadingMessage.isNotEmpty ? _loadingMessage : 'Chargement...',
                    style: const TextStyle(fontSize: 16),
                  ),
                  if (progress != null)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          LinearProgressIndicator(value: progress.progress),
                          const SizedBox(height: 8),
                          Text('${progress.current}/${progress.total} - ${progress.message}'),
                        ],
                      ),
                    ),
                ],
              ),
            )
          : _currentError != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _currentError!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _extractAndLoadSounds,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : Column(children: [
                  // Barre de recherche
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
                                      _cachedFilteredSounds = null;
                                      _resetPagination();
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
                        onChanged: _handleSearch,
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
                                    if (selected) _handleCategoryChange('');
                                  },
                                ),
                                const SizedBox(width: 8),
                                ...categories.map((category) => Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: FilterChip(
                                        label: Text(category),
                                        selected: _selectedCategory == category,
                                        onSelected: (selected) {
                                          _handleCategoryChange(selected ? category : '');
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
                                onSelected: _handleTexturesFilterChange,
                              ),
                              const Spacer(),
                              // Afficher le nombre de sons filtrés et le total
                              Text('${allFilteredSounds.length} sur ${_sounds.length} sons'),
                            ],
                          ),
                        ],
                      ),
                    ),

                  // Contenu principal
                  Expanded(
                    child: _buildContent(allFilteredSounds),
                  ),
                ]),
    );
  }

  Widget _buildContent(List<Sound> allFilteredSounds) {
    // Ne jamais masquer la liste pendant la recherche, uniquement au chargement initial
    if (_isLoading && _paginatedSounds.isEmpty && _searchQuery.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (allFilteredSounds.isEmpty) {
      return const Center(child: Text('Aucun son trouvé'));
    }

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          itemCount: _paginatedSounds.length + (_hasMoreItems ? 1 : 0),
          itemBuilder: (context, index) {
            // Si on est au dernier élément et qu'il y a plus d'éléments à charger
            if (index >= _paginatedSounds.length) {
              // Afficher un indicateur de chargement
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final sound = _paginatedSounds[index];
            final soundFullPath = sound.getFullPath(_extractedPath);

            // Vérifications lazy pour éviter des opérations coûteuses
            bool fileExists = false;
            bool hasTextures = false;
            List<String> texturesForSound = [];

            try {
              // Vérifier si le fichier existe (opération I/O potentiellement coûteuse)
              final file = File(soundFullPath);
              fileExists = file.existsSync();

              // Vérifier les textures uniquement si nécessaire
              if (_showOnlyWithTextures || _expandedSounds['${sound.category}/${sound.path}'] == true) {
                hasTextures = hasSoundTextures(soundFullPath);
                if (hasTextures) {
                  texturesForSound = getTexturesForSound(soundFullPath);
                }
              } else {
                // Faire une vérification légère pour l'affichage sans charger les textures
                hasTextures = hasSoundTextures(soundFullPath);
              }
            } catch (e) {
              debugPrint('Erreur lors de la vérification du son $soundFullPath: $e');
            }

            final soundId = '${sound.category}/${sound.path}';
            final isExpanded = _expandedSounds[soundId] ?? false;

            // Utiliser un RepaintBoundary pour isoler les redraws
            return RepaintBoundary(
              child: SoundCard(
                key: ValueKey(soundId), // Utiliser une clé pour optimiser les rebuilds
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
                onShowDetails: _showSoundMatchDetails,
              ),
            );
          },
        ),
        // Indicateur de chargement superposé qui ne cache pas la liste
        if (_isLoading && _paginatedSounds.isNotEmpty && _searchQuery.isNotEmpty)
          const Positioned(
            top: 0,
            right: 16,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Filtrage...', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showConfirmDialog(String title, String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text('Annuler'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text('Confirmer'),
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm();
            },
          ),
        ],
      ),
    );
  }

  /// Affiche les détails de correspondance pour un son spécifique
  void _showSoundMatchDetails(Sound sound) {
    final soundPath = sound.getFullPath(_extractedPath);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Détails: ${sound.name}'),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _getSoundMatchingDetails(soundPath),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Text('Erreur: ${snapshot.error}');
              }

              final details = snapshot.data!;

              if (details.isEmpty) {
                return const Text('Aucune correspondance trouvée');
              }

              return ListView(
                shrinkWrap: true,
                children: [
                  Text('Son: ${sound.path}.ogg'),
                  Text('Catégorie: ${sound.category}'),
                  Text('Dossier: ${_extractMaterial(soundPath)}'),
                  const SizedBox(height: 16),
                  const Text('Textures correspondantes:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...details.map((detail) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(path.basename(detail['texturePath']), style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('Score: ${detail['score']}'),
                              if (detail['texturePath'].toString().endsWith('.png'))
                                Image.file(
                                  File(detail['texturePath']),
                                  height: 100,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                                ),
                            ],
                          ),
                        ),
                      )),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Fermer'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: const Text('Régénérer l\'association'),
            onPressed: () {
              _regenerateCacheForSound(sound);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  /// Récupère les détails de correspondance pour un son
  Future<List<Map<String, dynamic>>> _getSoundMatchingDetails(String soundPath) async {
    try {
      // Le dossier du matériau (ex: bamboo)
      final material = _extractMaterial(soundPath);

      // Récupérer les textures correspondantes
      final textures = getTexturesForSound(soundPath);

      // Si aucune texture ne correspond, afficher un message explicatif
      if (textures.isEmpty) {
        // Rechercher toutes les textures disponibles pour comprendre pourquoi aucune correspondance
        final texturesDir = Directory('$_extractedPath/assets/minecraft/textures');
        final texturesExact = _findExactMaterialTextures(texturesDir.path, material);

        if (texturesExact.isNotEmpty) {
          // Il y a des textures mais elles n'ont pas été associées
          final result = <Map<String, dynamic>>[];
          for (final texturePath in texturesExact) {
            result.add({
              'texturePath': texturePath,
              'score': -1, // Score spécial pour indiquer que c'est une suggestion
              'matches': '$material (suggestion, non associé)',
            });
          }
          return result;
        }
      }

      // Analyser les textures correspondantes
      final List<Map<String, dynamic>> result = [];
      for (final texturePath in textures) {
        final textureName = path.basenameWithoutExtension(path.basename(texturePath));

        // Calculer un score réel basé sur les mêmes règles que l'algorithme principal
        int score = 0;

        if (textureName.toLowerCase() == material.toLowerCase()) {
          score = 1000; // Correspondance exacte
        } else if (textureName.toLowerCase() == '${material.toLowerCase()}_block') {
          score = 900; // Correspondance avec _block
        } else if (_containsWholeWord(textureName.toLowerCase(), material.toLowerCase())) {
          score = 500; // Contient le matériau comme mot entier
        } else if (textureName.toLowerCase().contains(material.toLowerCase()) && material.length > 3) {
          score = 300; // Contient le matériau comme sous-chaîne
        }

        if (texturePath.contains('/$material/')) {
          score += 200; // Matériau présent dans le chemin
        }

        result.add({
          'texturePath': texturePath,
          'score': score,
          'matches': material,
        });
      }

      // Trier par score
      result.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

      return result;
    } catch (e) {
      debugPrint('Erreur lors de l\'analyse de $soundPath: $e');
      return [];
    }
  }

  /// Recherche les textures contenant le nom exact du matériau
  List<String> _findExactMaterialTextures(String texturesBasePath, String material) {
    try {
      final result = <String>[];
      final dir = Directory(texturesBasePath);

      if (!dir.existsSync()) return [];

      // Recherche récursive dans le dossier de textures
      final entities = dir.listSync(recursive: true);

      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.png')) {
          final fileName = path.basenameWithoutExtension(entity.path).toLowerCase();

          if (fileName == material.toLowerCase() || fileName == '${material.toLowerCase()}_block' || _containsWholeWord(fileName, material.toLowerCase())) {
            result.add(entity.path);
          }
        }
      }

      return result;
    } catch (e) {
      debugPrint('Erreur lors de la recherche de textures pour $material: $e');
      return [];
    }
  }

  /// Vérifie si un texte contient un mot entier
  bool _containsWholeWord(String text, String word) {
    if (text == word) return true;

    if (text.startsWith(word) && text.length > word.length) {
      final charAfter = text[word.length];
      if (charAfter == '_' || charAfter == ' ' || charAfter == '-') return true;
    }

    if (text.endsWith(word) && text.length > word.length) {
      final charBefore = text[text.length - word.length - 1];
      if (charBefore == '_' || charBefore == ' ' || charBefore == '-') return true;
    }

    for (final sep in [
      '_',
      ' ',
      '-'
    ]) {
      if (text.contains('$sep$word$sep')) return true;
    }

    return false;
  }

  /// Extrait le nom du matériau à partir du chemin d'un son
  String _extractMaterial(String soundPath) {
    final dir = path.dirname(soundPath);
    return path.basename(dir);
  }

  /// Régénère le cache spécifiquement pour un son
  Future<void> _regenerateCacheForSound(Sound sound) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Vider les caches
      _soundTextureCache.clear();
      _texturesForSoundCache.clear();
      _cachedFilteredSounds = null;

      // Forcer une régénération complète
      await _resourceMatcher.invalidateCache(_extractedPath);
      final newMatches = await _resourceMatcher.loadOrGenerateSoundTextureMatches(_extractedPath);

      setState(() {
        _soundToTextures = newMatches;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Associations régénérées avec succès')),
      );

      // Recharger la page
      _resetPagination();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }
}
