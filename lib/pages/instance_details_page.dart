import 'package:flutter/material.dart';
import '../services/curseforge_service.dart';
import 'resource_pack_sounds_page.dart';

class InstanceDetailsPage extends StatefulWidget {
  final String instanceName;

  const InstanceDetailsPage({
    super.key,
    required this.instanceName,
  });

  @override
  State<InstanceDetailsPage> createState() => _InstanceDetailsPageState();
}

class _InstanceDetailsPageState extends State<InstanceDetailsPage> {
  final CurseForgeService _curseForgeService = CurseForgeService();
  List<String> _resourcePacks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadResourcePacks();
  }

  Future<void> _loadResourcePacks() async {
    setState(() {
      _isLoading = true;
    });

    final resourcePacks = await _curseForgeService.getResourcePacks(widget.instanceName);

    setState(() {
      _resourcePacks = resourcePacks;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.instanceName),
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
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ResourcePackSoundsPage(
                              instanceName: widget.instanceName,
                              resourcePackName: _resourcePacks[index],
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
