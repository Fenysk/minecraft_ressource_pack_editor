import 'package:flutter/material.dart';
import '../services/curseforge_service.dart';
import 'instance_details_page.dart';

class CurseForgeInstancesPage extends StatefulWidget {
  const CurseForgeInstancesPage({super.key});

  @override
  State<CurseForgeInstancesPage> createState() => _CurseForgeInstancesPageState();
}

class _CurseForgeInstancesPageState extends State<CurseForgeInstancesPage> {
  final CurseForgeService _curseForgeService = CurseForgeService();
  List<String> _instances = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInstances();
  }

  Future<void> _loadInstances() async {
    setState(() {
      _isLoading = true;
    });

    final instances = await _curseForgeService.getInstances();

    setState(() {
      _instances = instances;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Instances CurseForge'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _instances.isEmpty
              ? const Center(child: Text('Aucune instance CurseForge trouvée'))
              : ListView.builder(
                  itemCount: _instances.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(_instances[index]),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => InstanceDetailsPage(
                              instanceName: _instances[index],
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
