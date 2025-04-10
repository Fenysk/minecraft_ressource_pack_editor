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

      final fileSize = await file.length();
      print('Lecture du fichier: $filePath (taille: ${fileSize ~/ 1024} KB)');

      // Arrêter la lecture précédente
      await _audioPlayer.stop();
      _isPlaying = false;

      // Stocker le dernier fichier joué
      _lastPlayedFile = filePath;

      // Configurer le lecteur audio
      await _audioPlayer.setVolume(1.0);

      // Tenter la lecture avec différents formats de chemin
      try {
        // Format 1: Chemin Windows standard
        print('Tentative avec chemin Windows standard');
        final normalizedPath = filePath.replaceAll('/', '\\');
        await _audioPlayer.setFilePath(normalizedPath);
        await _audioPlayer.play();
        _isPlaying = true;
        print('Lecture démarrée avec succès (format Windows)');
      } catch (e1) {
        print('Échec de lecture avec format Windows: $e1');
        try {
          // Format 2: Chemin avec slash
          print('Tentative avec chemin style URL');
          final urlPath = filePath.replaceAll('\\', '/');
          await _audioPlayer.setFilePath(urlPath);
          await _audioPlayer.play();
          _isPlaying = true;
          print('Lecture démarrée avec succès (format URL)');
        } catch (e2) {
          print('Échec de lecture avec format URL: $e2');
          try {
            // Format 3: URL file://
            print('Tentative avec file:// URL');
            final fileUrl = 'file://${filePath.replaceAll('\\', '/')}';
            await _audioPlayer.setUrl(fileUrl);
            await _audioPlayer.play();
            _isPlaying = true;
            print('Lecture démarrée avec succès (format file://)');
          } catch (e3) {
            print('Échec de lecture avec format file://: $e3');
            throw Exception('Impossible de lire le fichier audio après plusieurs tentatives');
          }
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

  String? getLastPlayedFile() {
    return _lastPlayedFile;
  }

  bool get isPlaying => _isPlaying;
}
