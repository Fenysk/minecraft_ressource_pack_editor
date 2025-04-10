import 'package:flutter/material.dart';
import '../services/curseforge_service.dart';
import '../models/sound.dart';
import '../services/audio_service.dart';
import 'dart:io';

class ResourcePackSoundsPage extends StatefulWidget {
  final String instanceName;
  final String resourcePackName;

  const ResourcePackSoundsPage({
    super.key,
    required this.instanceName,
    required this.resourcePackName,
  });

  @override
  State<ResourcePackSoundsPage> createState() => _ResourcePackSoundsPageState();
}

class _ResourcePackSoundsPageState extends State<ResourcePackSoundsPage> {
  final CurseForgeService _curseForgeService = CurseForgeService();
  final AudioService _audioService = AudioService();
  List<Sound> _sounds = [];
  bool _isLoading = true;
  String _selectedCategory = '';
  String _extractedPath = '';
  String? _currentError;
  Sound? _currentlyPlayingSound;

  @override
  void initState() {
    super.initState();
    _extractAndLoadSounds();
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _extractAndLoadSounds() async {
    setState(() {
      _isLoading = true;
      _currentError = null;
    });

    try {
      await _curseForgeService.extractResourcePack(
        widget.instanceName,
        widget.resourcePackName,
      );

      final instancePath = await _curseForgeService.getInstancePath(widget.instanceName);
      _extractedPath = '$instancePath\\extracted\\${widget.resourcePackName}';

      print('Chemin d\'extraction utilisé pour les sons: $_extractedPath');

      final sounds = await _curseForgeService.getResourcePackSounds(
        widget.instanceName,
        widget.resourcePackName,
      );

      setState(() {
        _sounds = sounds;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _currentError = 'Erreur lors du chargement: $e';
        _isLoading = false;
      });
      print('Erreur lors du chargement: $e');
    }
  }

  List<String> getCategories() {
    return _sounds.map((s) => s.category).toSet().toList()..sort();
  }

  List<Sound> getSoundsByCategory(String category) {
    return _sounds.where((s) => s.category == category).toList();
  }

  Future<void> _playSoundWithErrorHandling(String soundPath, Sound sound) async {
    _audioService.stop();

    setState(() {
      _currentError = null;
      _currentlyPlayingSound = sound;
    });

    try {
      print('Tentative de lecture: $soundPath');
      await _audioService.playSound(soundPath);
    } catch (e) {
      setState(() {
        _currentError = 'Erreur de lecture: $e';
        _currentlyPlayingSound = null;
      });
      print('Erreur finale de lecture: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.resourcePackName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _extractAndLoadSounds,
            tooltip: 'Rafraîchir',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sounds.isEmpty
              ? const Center(child: Text('Aucun son trouvé'))
              : Column(
                  children: [
                    if (_currentError != null)
                      Container(
                        color: Colors.red.shade100,
                        padding: const EdgeInsets.all(8.0),
                        width: double.infinity,
                        child: Text(
                          _currentError!,
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),
                    if (_currentlyPlayingSound != null)
                      Container(
                        color: Colors.blue.shade100,
                        padding: const EdgeInsets.all(8.0),
                        width: double.infinity,
                        child: Row(
                          children: [
                            const Icon(Icons.play_arrow, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'En lecture: ${_currentlyPlayingSound!.name}',
                                style: TextStyle(color: Colors.blue.shade900),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.stop, color: Colors.blue),
                              onPressed: () {
                                _audioService.stop();
                                setState(() {
                                  _currentlyPlayingSound = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    Container(
                      height: 60,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          children: [
                            for (var category in getCategories())
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: FilterChip(
                                  label: Text(category),
                                  selected: _selectedCategory == category,
                                  onSelected: (selected) {
                                    setState(() {
                                      _selectedCategory = selected ? category : '';
                                    });
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _selectedCategory.isEmpty ? _sounds.length : getSoundsByCategory(_selectedCategory).length,
                        itemBuilder: (context, index) {
                          final sound = _selectedCategory.isEmpty ? _sounds[index] : getSoundsByCategory(_selectedCategory)[index];

                          final soundPath = '$_extractedPath\\assets\\minecraft\\sounds\\${sound.path}.ogg';
                          final fileExists = File(soundPath).existsSync();

                          return ListTile(
                            leading: Icon(
                              Icons.audiotrack,
                              color: fileExists ? (_currentlyPlayingSound == sound ? Colors.blue : Colors.green) : Colors.red,
                            ),
                            title: Text(sound.name),
                            subtitle: Text(fileExists ? '${sound.category} (${sound.path})' : 'Fichier non trouvé: ${sound.path}.ogg'),
                            onTap: () async {
                              if (fileExists) {
                                await _playSoundWithErrorHandling(soundPath, sound);
                              } else {
                                setState(() {
                                  _currentError = 'Fichier introuvable: ${sound.path}.ogg';
                                });
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
