import 'dart:io';
import 'package:just_audio/just_audio.dart';

class AudioService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _lastPlayedFile;
  bool _isPlaying = false;

  AudioService();

  Future<void> playSound(String filePath) async {
    try {
      // Vérifier si le fichier existe
      final file = File(filePath);
      if (!file.existsSync()) {
        throw Exception('Fichier introuvable: $filePath');
      }

      // Arrêter la lecture précédente
      await _audioPlayer.stop();
      _isPlaying = false;
      _lastPlayedFile = filePath;

      // Normaliser le chemin pour être compatible avec just_audio
      final normalizedPath = filePath.replaceAll('\\', '/');

      try {
        await _audioPlayer.setFilePath(normalizedPath);
        await _audioPlayer.play();
        _isPlaying = true;
      } catch (e) {
        // Essayer avec le préfixe file:// si la première méthode échoue
        try {
          final fileUrl = 'file://$normalizedPath';
          await _audioPlayer.setUrl(fileUrl);
          await _audioPlayer.play();
          _isPlaying = true;
        } catch (e2) {
          throw Exception('Impossible de lire le fichier audio: $e2');
        }
      }
    } catch (e) {
      print('Erreur lors de la lecture du son: $e');
      throw e;
    }
  }

  void stop() async {
    await _audioPlayer.stop();
    _isPlaying = false;
  }

  void dispose() async {
    await _audioPlayer.dispose();
    _isPlaying = false;
  }

  String? get lastPlayedFile => _lastPlayedFile;
  bool get isPlaying => _isPlaying;
}
