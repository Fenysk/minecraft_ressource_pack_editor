/// Représente une correspondance entre une texture et ses sons associés
class ResourceMatch {
  final String texturePath;
  final List<String> soundPaths;

  ResourceMatch({required this.texturePath, required this.soundPaths});

  Map<String, dynamic> toJson() {
    return {
      'texturePath': texturePath,
      'soundPaths': soundPaths,
    };
  }

  factory ResourceMatch.fromJson(Map<String, dynamic> json) {
    return ResourceMatch(
      texturePath: json['texturePath'],
      soundPaths: List<String>.from(json['soundPaths']),
    );
  }
}

/// Représente une correspondance entre un son et ses textures associées
class SoundTextureMatch {
  final String soundPath;
  final List<String> texturePaths;

  SoundTextureMatch({required this.soundPath, required this.texturePaths});

  Map<String, dynamic> toJson() {
    return {
      'soundPath': soundPath,
      'texturePaths': texturePaths,
    };
  }

  factory SoundTextureMatch.fromJson(Map<String, dynamic> json) {
    return SoundTextureMatch(
      soundPath: json['soundPath'],
      texturePaths: List<String>.from(json['texturePaths']),
    );
  }
}
