import 'dart:io';
import 'package:flutter/material.dart';
import 'package:minecraft_ressource_pack_editor/models/sound.dart';
import 'package:path/path.dart' as p;

class SoundCard extends StatelessWidget {
  final Sound sound;
  final String soundPath;
  final bool fileExists;
  final bool hasTextures;
  final List<Map<String, dynamic>> texturesForSound;
  final bool isExpanded;
  final Sound? currentlyPlayingSound;
  final String extractedPath;
  final Function(String, Sound) onPlaySound;
  final Function(Sound)? onToggleExpand;
  final Function(Sound)? onShowDetails;

  const SoundCard({
    super.key,
    required this.sound,
    required this.soundPath,
    required this.fileExists,
    required this.hasTextures,
    required this.texturesForSound,
    required this.isExpanded,
    required this.currentlyPlayingSound,
    required this.extractedPath,
    required this.onPlaySound,
    this.onToggleExpand,
    this.onShowDetails,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = currentlyPlayingSound == sound;
    final textureCount = texturesForSound.length;

    // Trier les textures par score (au cas où elles n'ont pas été triées)
    if (textureCount > 0) {
      texturesForSound.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    }

    // Log pour débogage
    debugPrint('SoundCard pour ${sound.name}: hasTextures=$hasTextures, textureCount=$textureCount');
    if (hasTextures && textureCount > 0) {
      debugPrint('Meilleure texture: ${texturesForSound.first['path']}, score: ${texturesForSound.first['score']}');
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: onToggleExpand != null ? () => onToggleExpand!(sound) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // La tuile principale avec les informations du son
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Partie gauche avec l'icône du son
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(
                      Icons.audiotrack,
                      color: _getSoundIconColor(isPlaying),
                      size: 32,
                    ),
                  ),

                  // Partie centrale avec les informations
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sound.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            fileExists ? '${sound.category} (${sound.path})' : 'Fichier non trouvé: ${sound.path}.ogg',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          if (hasTextures && textureCount > 0)
                            Row(
                              children: [
                                Text(
                                  'Textures ($textureCount): ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: Builder(builder: (context) {
                                      try {
                                        final texturePath = texturesForSound.first['path'] as String;
                                        final score = texturesForSound.first['score'] as int;
                                        return Stack(
                                          children: [
                                            Image.file(
                                              File(texturePath),
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                debugPrint('Erreur chargement image: $error');
                                                return Container(
                                                  color: Colors.grey.shade200,
                                                  child: const Icon(Icons.image_not_supported, size: 10),
                                                );
                                              },
                                            ),
                                            Positioned(
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                  color: _getScoreColor(score),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      } catch (e) {
                                        debugPrint('Erreur structure texture: $e');
                                        return Container(
                                          color: Colors.red.shade200,
                                          child: const Icon(Icons.error_outline, size: 10),
                                        );
                                      }
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                if (textureCount > 0)
                                  Text(
                                    'Score: ${texturesForSound.first['score']}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _getScoreColor(texturesForSound.first['score'] as int),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            )
                          else
                            Text(
                              'Aucune texture associée',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Afficher directement la première texture associée (s'il y en a)
                  if (hasTextures && textureCount > 0) _buildThumbnail(),

                  // Bouton de lecture
                  if (fileExists)
                    IconButton(
                      icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                      onPressed: () => onPlaySound(soundPath, sound),
                    ),

                  // Bouton pour afficher les détails
                  if (onShowDetails != null)
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      tooltip: 'Afficher les détails',
                      onPressed: () => onShowDetails!(sound),
                    ),
                ],
              ),
            ),

            // Affichage des textures si le son est étendu
            if (isExpanded && hasTextures && textureCount > 0)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: texturesForSound.map((textureInfo) {
                    try {
                      final path = textureInfo['path'] as String;
                      final score = textureInfo['score'] as int;
                      return Column(
                        children: [
                          Stack(
                            children: [
                              _buildThumbnail(path),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getScoreColor(score),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    score.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            p.basename(path),
                            style: const TextStyle(fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      );
                    } catch (e) {
                      debugPrint('Erreur structure texture (expanded): $e');
                      return Container(
                        width: 50,
                        height: 50,
                        color: Colors.red.shade200,
                        child: const Icon(Icons.error_outline),
                      );
                    }
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Retourne la couleur de l'icône en fonction de l'état du son
  Color _getSoundIconColor(bool isPlaying) {
    if (!fileExists) return Colors.red;
    if (isPlaying) return Colors.blue;
    return Colors.green;
  }

  /// Returns a color based on the score value
  Color _getScoreColor(int score) {
    if (score >= 1000) return Colors.green.shade700;
    if (score >= 500) return Colors.blue.shade700;
    if (score >= 100) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  /// Construit une vignette pour une texture
  Widget _buildThumbnail([String? texturePath]) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 50,
        height: 50,
        child: Builder(builder: (context) {
          try {
            // Si un chemin est fourni, l'utiliser directement
            final path = texturePath ?? (texturesForSound.isNotEmpty ? texturesForSound.first['path'] as String : '');
            final score = texturePath == null && texturesForSound.isNotEmpty
                ? texturesForSound.first['score'] as int
                : texturesForSound.firstWhere((t) => t['path'] == texturePath,
                        orElse: () => {
                              'score': 0
                            })['score'] as int? ??
                    0;

            if (path.isEmpty) {
              return Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.image_not_supported, size: 24),
              );
            }

            return Stack(
              children: [
                // Fond de couleur pour les scores parfaits
                if (score >= 1000)
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.green.shade600,
                        width: 2,
                      ),
                    ),
                  ),

                // Image de la texture
                Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('Erreur chargement image: $error');
                    return Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image_not_supported, size: 24),
                    );
                  },
                ),

                // Indicateur de score
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getScoreColor(score).withOpacity(0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      score.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // Badge spécial pour les correspondances parfaites
                if (score >= 1000)
                  Positioned(
                    left: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            );
          } catch (e) {
            debugPrint('Erreur structure texture: $e');
            return Container(
              color: Colors.red.shade200,
              child: const Icon(Icons.error_outline, size: 24),
            );
          }
        }),
      ),
    );
  }
}
