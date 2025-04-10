class Sound {
  final String name;
  final String path;
  final String category; // block, entity, music, etc.
  final String? texture; // Texture associée si applicable
  final bool isCustom; // Si c'est un son personnalisé

  Sound({
    required this.name,
    required this.path,
    required this.category,
    this.texture,
    this.isCustom = false,
  });

  /// Crée une copie du son avec de nouvelles propriétés
  Sound copyWith({
    String? name,
    String? path,
    String? category,
    String? texture,
    bool? isCustom,
  }) {
    return Sound(
      name: name ?? this.name,
      path: path ?? this.path,
      category: category ?? this.category,
      texture: texture ?? this.texture,
      isCustom: isCustom ?? this.isCustom,
    );
  }

  /// Retourne le chemin complet du fichier son
  String getFullPath(String basePath) {
    // Utiliser path.join pour une meilleure compatibilité multiplateforme
    return [
      basePath,
      'assets',
      'minecraft',
      'sounds',
      '$path.ogg'
    ].join('/');
  }

  @override
  String toString() => 'Sound(name: $name, path: $path, category: $category, isCustom: $isCustom)';
}
