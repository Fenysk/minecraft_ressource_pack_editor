import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/curseforge_service.dart';
import '../main.dart';
import 'instance_details_page.dart';

class CurseForgeInstancesPage extends StatefulWidget {
  final Function? toggleTheme;

  const CurseForgeInstancesPage({
    super.key,
    this.toggleTheme,
  });

  @override
  State<CurseForgeInstancesPage> createState() => _CurseForgeInstancesPageState();
}

class _CurseForgeInstancesPageState extends State<CurseForgeInstancesPage> {
  late final CurseForgeService _curseForgeService;
  List<String> instances = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _curseForgeService = Provider.of<CurseForgeService>(context, listen: false);
    _loadInstances();
  }

  Future<void> _loadInstances() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final curseForgeInstances = await _curseForgeService.getInstances();
      setState(() {
        instances = curseForgeInstances;
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
        title: const Text('Instances CurseForge'),
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
          : instances.isEmpty
              ? const Center(child: Text('Aucune instance trouvée'))
              : ListView.builder(
                  itemCount: instances.length,
                  itemBuilder: (context, index) {
                    final instance = instances[index];
                    return ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(instance),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => InstanceDetailsPage(
                              instanceName: instance,
                              toggleTheme: widget.toggleTheme,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
