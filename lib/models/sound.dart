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
}
