import 'dart:io';
import 'package:flutter/material.dart';
import 'package:minecraft_ressource_pack_editor/models/sound.dart';

class SoundCard extends StatelessWidget {
  final Sound sound;
  final String soundPath;
  final bool fileExists;
  final bool hasTextures;
  final List<String> texturesForSound;
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
                            Text(
                              'Textures: $textureCount',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                              ),
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
                  if (hasTextures && texturesForSound.isNotEmpty) _buildThumbnail(texturesForSound.first),

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
            if (isExpanded && hasTextures && texturesForSound.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: texturesForSound.map((texturePath) => _buildThumbnail(texturePath)).toList(),
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

  /// Construit une vignette pour une texture
  Widget _buildThumbnail(String texturePath) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        File(texturePath),
        width: 50,
        height: 50,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 50,
            height: 50,
            color: Colors.grey.shade200,
            child: const Icon(Icons.image_not_supported, size: 24),
          );
        },
      ),
    );
  }
}
