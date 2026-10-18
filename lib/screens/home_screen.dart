import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/player_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _addonService = AddonService();
  late final PlayerService _player;

  final _urlController = TextEditingController();
  final _searchController = TextEditingController();

  List<InstalledAddon> _addons = [];
  List<TrackResult> _results = [];
  bool _loadingAddons = true;
  bool _searching = false;
  bool _adding = false;
  String? _status;
  bool _showAddons = true;

  @override
  void initState() {
    super.initState();
    _player = PlayerService(addonService: _addonService);
    _loadAddons();
  }

  Future<void> _loadAddons() async {
    final list = await _addonService.load();
    if (!mounted) return;
    setState(() {
      _addons = list;
      _loadingAddons = false;
    });
  }

  Future<void> _addAddon() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() => _adding = true);
    try {
      final installed = await _addonService.fetchAndBuild(url);
      final next = List<InstalledAddon>.from(_addons);
      final idx = next.indexWhere(
        (a) => a.baseUrl == installed.baseUrl || a.manifest.id == installed.manifest.id,
      );
      if (idx >= 0) {
        next[idx] = installed;
      } else {
        next.add(installed);
      }
      await _addonService.save(next);
      if (!mounted) return;
      setState(() {
        _addons = next;
        _urlController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Add failed: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeAddon(InstalledAddon addon) async {
    final next = _addons.where((a) => a.baseUrl != addon.baseUrl).toList();
    await _addonService.save(next);
    if (!mounted) return;
    setState(() => _addons = next);
  }

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    if (_addons.where((a) => a.manifest.canSearch).isEmpty) {
      setState(() => _status = 'Add a search-capable addon first.');
      return;
    }
    setState(() {
      _searching = true;
      _status = 'Searching…';
      _results = [];
    });
    final tracks = await _addonService.search(_addons, q);
    if (!mounted) return;
    setState(() {
      _results = tracks;
      _searching = false;
      _status = '${tracks.length} track(s)';
    });
  }

  Future<void> _play(TrackResult track) async {
    setState(() => _status = 'Loading stream…');
    try {
      await _player.playTrack(track);
      if (!mounted) return;
      setState(() => _status = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Play failed: $e');
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      headers: [
        AppBar(
          title: const Text('Orchid'),
          subtitle: const Text('Eclipse addons'),
        ),
      ],
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _addonsSection(),
                const SizedBox(height: 20),
                _searchSection(),
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Text(_status!).muted(),
                ],
                const SizedBox(height: 12),
                ..._results.map(_trackTile),
              ],
            ),
          ),
          _playerBar(),
        ],
      ),
    );
  }

  Widget _addonsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('Addons').large().semiBold(),
                const Spacer(),
                GhostButton(
                  onPressed: () => setState(() => _showAddons = !_showAddons),
                  child: Text(_showAddons ? 'Hide' : 'Show'),
                ),
              ],
            ),
            if (_showAddons) ...[
              const SizedBox(height: 10),
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
              const SizedBox(height: 8),
              const Text(
                'Paste any Eclipse-compatible addon URL.',
              ).small().muted(),
              const SizedBox(height: 12),
              if (_loadingAddons)
                const Text('Loading…').muted()
              else if (_addons.isEmpty)
                const Text('No addons yet.').muted()
              else
                ..._addons.map((a) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.manifest.name).semiBold(),
                              Text(
                                '${a.baseUrl} · ${a.manifest.resources.join(", ")} · v${a.manifest.version}',
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
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _searchSection() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            placeholder: const Text('Search songs…'),
            onSubmitted: (_) => _search(),
          ),
        ),
        const SizedBox(width: 8),
        PrimaryButton(
          onPressed: _searching ? null : _search,
          child: Text(_searching ? '…' : 'Search'),
        ),
      ],
    );
  }

  Widget _trackTile(TrackResult t) {
    return Button(
      style: const ButtonStyle.ghost(),
      onPressed: () => _play(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (t.artworkUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: t.artworkUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox(width: 48, height: 48),
                ),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.muted,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title).semiBold(),
                  Text(
                    [t.artist, if (t.album != null) t.album].join(' · '),
                  ).small().muted(),
                  Text(t.addonName).xSmall().muted(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerBar() {
    final track = _player.current;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.border),
        ),
        color: Theme.of(context).colorScheme.card,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (track?.artworkUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: track!.artworkUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            )
          else
            const SizedBox(width: 44, height: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(track?.title ?? 'Nothing playing').semiBold(),
                Text(track?.artist ?? '—').small().muted(),
              ],
            ),
          ),
          IconButton.ghost(
            onPressed: track == null
                ? null
                : () async {
                    await _player.togglePlayPause();
                    setState(() {});
                  },
            icon: Icon(
              _player.player.playing ? LucideIcons.pause : LucideIcons.play,
            ),
          ),
        ],
      ),
    );
  }
}
