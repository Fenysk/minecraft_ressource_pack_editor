import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/curseforge_service.dart';
import 'resource_pack_sounds_page.dart';

class InstanceDetailsPage extends StatefulWidget {
  final String instanceName;
  final Function? toggleTheme;

  const InstanceDetailsPage({
    super.key,
    required this.instanceName,
    this.toggleTheme,
  });

  @override
  State<InstanceDetailsPage> createState() => _InstanceDetailsPageState();
}

class _InstanceDetailsPageState extends State<InstanceDetailsPage> {
  late final CurseForgeService _curseForgeService;
  List<String> _resourcePacks = [];
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
      final resourcePacks = await _curseForgeService.getResourcePacks(widget.instanceName);
      setState(() {
        _resourcePacks = resourcePacks;
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
        title: Text(widget.instanceName),
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
          : _resourcePacks.isEmpty
              ? const Center(child: Text('Aucun resource pack trouvé'))
              : ListView.builder(
                  itemCount: _resourcePacks.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(_resourcePacks[index]),
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          '/resource_pack_sounds',
                          arguments: {
                            'instanceName': widget.instanceName,
                            'resourcePackName': _resourcePacks[index],
                          },
                        );
                      },
                    );
                  },
                ),
    );
  }
}
