import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';

class SettingsScreen extends StatefulWidget {
  final AddonService addonService;
  final List<InstalledAddon> addons;
  final ValueChanged<List<InstalledAddon>> onAddonsChanged;

  const SettingsScreen({
    super.key,
    required this.addonService,
    required this.addons,
    required this.onAddonsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  bool _adding = false;
  String? _status;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _addAddon() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _adding = true;
      _status = null;
    });
    try {
      final installed = await widget.addonService.fetchAndBuild(url);
      final next = List<InstalledAddon>.from(widget.addons);
      final idx = next.indexWhere(
        (a) =>
            a.baseUrl == installed.baseUrl ||
            a.manifest.id == installed.manifest.id,
      );
      if (idx >= 0) {
        next[idx] = installed;
      } else {
        next.add(installed);
      }
      await widget.addonService.save(next);
      widget.onAddonsChanged(next);
      if (!mounted) return;
      setState(() {
        _urlController.clear();
        _status = 'Added ${installed.manifest.name}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Add failed: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeAddon(InstalledAddon addon) async {
    final next =
        widget.addons.where((a) => a.baseUrl != addon.baseUrl).toList();
    await widget.addonService.save(next);
    widget.onAddonsChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Sources').large().semiBold(),
        const SizedBox(height: 8),
        const Text(
          'Built-in search uses iTunes. Add Eclipse-compatible addons for full streams.',
        ).small().muted(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Built-in').semiBold(),
                const SizedBox(height: 8),
                _builtInRow(
                  'iTunes',
                  'Search + 30s previews when no stream matches',
                ),
                const SizedBox(height: 6),
                _builtInRow(
                  'Spicy Lyrics',
                  'Syllable / line sync · attribution required',
                ),
                const SizedBox(height: 6),
                _builtInRow(
                  'Spotify API',
                  'Fallback search for track IDs (lyrics)',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Eclipse addons').semiBold(),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                placeholder: const Text('https://addon…/ or …/manifest.json'),
                onSubmitted: (_) => _addAddon(),
              ),
            ),
            const SizedBox(width: 8),
            PrimaryButton(
              onPressed: _adding ? null : _addAddon,
              child: Text(_adding ? '…' : 'Add'),
            ),
          ],
        ),
        if (_status != null) ...[
          const SizedBox(height: 8),
          Text(_status!).small().muted(),
        ],
        const SizedBox(height: 12),
        if (widget.addons.isEmpty)
          const Text('No external addons yet.').muted()
        else
          ...widget.addons.map((a) {
            final caps = <String>[
              if (a.manifest.canSearch) 'search',
              if (a.manifest.canStream) 'stream',
            ].join(', ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.manifest.name).semiBold(),
                            Text(
                              '${a.baseUrl}\n$caps · v${a.manifest.version}',
                            ).small().muted(),
                          ],
                        ),
                      ),
                      GhostButton(
                        onPressed: () => _removeAddon(a),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _builtInRow(String title, String subtitle) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              Text(subtitle).xSmall().muted(),
            ],
          ),
        ),
        const Text('on').xSmall().muted(),
      ],
    );
  }
}
