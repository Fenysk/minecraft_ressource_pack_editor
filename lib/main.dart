import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pages/curseforge_instances_page.dart';
import 'services/curseforge_service.dart';
import 'pages/resource_pack_sounds_page.dart';
import 'services/audio_service.dart';
import 'services/resource_matcher_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CurseForgeService().checkPermissions(); // Vérifie les permissions au démarrage

  // Capture des erreurs non gérées
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Uncaught exception: ${details.exception}');
  };

  runApp(MultiProvider(
    providers: [
      Provider<CurseForgeService>(create: (_) => CurseForgeService()),
      Provider<AudioService>(create: (_) => AudioService()),
      Provider<ResourceMatcherService>(create: (_) => ResourceMatcherService()),
    ],
    child: const MinecraftResourcePackEditor(),
  ));
}

class MinecraftResourcePackEditor extends StatefulWidget {
  const MinecraftResourcePackEditor({super.key});

  @override
  State<MinecraftResourcePackEditor> createState() => _MinecraftResourcePackEditorState();
}

class _MinecraftResourcePackEditorState extends State<MinecraftResourcePackEditor> {
  ThemeMode _themeMode = ThemeMode.light;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minecraft Resource Pack Editor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: CurseForgeInstancesPage(toggleTheme: toggleTheme),
      routes: {
        '/instances': (context) => CurseForgeInstancesPage(toggleTheme: toggleTheme),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/resource_pack_sounds') {
          final args = settings.arguments as Map<String, String>;
          return MaterialPageRoute(
            builder: (context) => ResourcePackSoundsPage(
              instanceName: args['instanceName']!,
              resourcePackName: args['resourcePackName']!,
              toggleTheme: toggleTheme,
              extractedPath: '',
            ),
          );
        }
        return null;
      },
    );
  }
}

class InstanceResourcePacksPage extends StatefulWidget {
  final String instanceName;
  final Function? toggleTheme;

  const InstanceResourcePacksPage({
    super.key,
    required this.instanceName,
    this.toggleTheme,
  });

  @override
  State<InstanceResourcePacksPage> createState() => _InstanceResourcePacksPageState();
}

class _InstanceResourcePacksPageState extends State<InstanceResourcePacksPage> {
  late final CurseForgeService _curseForgeService;
  List<String> resourcePacks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _curseForgeService = Provider.of<CurseForgeService>(context, listen: false);
    _loadResourcePacks();
  }

  Future<void> _loadResourcePacks() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final packs = await _curseForgeService.getResourcePacks(widget.instanceName);
      setState(() {
        resourcePacks = packs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('Resource Packs de ${widget.instanceName}'),
        actions: [
          IconButton(
            icon: Icon(Theme.of(context).brightness == Brightness.light ? Icons.dark_mode : Icons.light_mode),
            onPressed: () {
              if (widget.toggleTheme != null) widget.toggleTheme!();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : resourcePacks.isEmpty
              ? const Center(child: Text('Aucun resource pack trouvé'))
              : ListView.builder(
                  itemCount: resourcePacks.length,
                  itemBuilder: (context, index) {
                    final resourcePack = resourcePacks[index];
                    return ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(resourcePack),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.music_note),
                            tooltip: 'Voir les sons',
                            onPressed: () {
                              Navigator.pushNamed(
                                context,
                                '/resource_pack_sounds',
                                arguments: {
                                  'instanceName': widget.instanceName,
                                  'resourcePackName': resourcePack,
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
