import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/player_service.dart';

class SearchScreen extends StatefulWidget {
  final AddonService addonService;
  final PlayerService player;
  final List<InstalledAddon> addons;

  const SearchScreen({
    super.key,
    required this.addonService,
    required this.player,
    required this.addons,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  List<TrackResult> _results = [];
  bool _searching = false;
  String? _status;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _searching = true;
      _status = 'Searching…';
      _results = [];
    });

    final tracks = await widget.addonService.search(widget.addons, q);
    if (!mounted) return;
    setState(() {
      _results = tracks;
      _searching = false;
      _status = tracks.isEmpty ? 'No results' : '${tracks.length} track(s)';
    });
  }

  Future<void> _play(TrackResult track) async {
    setState(() => _status = 'Resolving…');
    try {
      widget.player.setAddons(widget.addons);
      await widget.player.playTrack(track, fromQueue: _results);
      if (!mounted) return;
      setState(() {
        _status = widget.player.playingVia != null
            ? 'Playing via ${widget.player.playingVia}'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Play failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
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
          ),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_status!).small().muted(),
            ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: _results.length,
            itemBuilder: (context, i) => _trackTile(_results[i]),
          ),
        ),
      ],
    );
  }

  Widget _trackTile(TrackResult t) {
    final playing = widget.player.current?.id == t.id &&
        widget.player.current?.sourceId == t.sourceId;

    return Button(
      style: const ButtonStyle.ghost(),
      onPressed: () => _play(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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
                  errorWidget: (_, __, ___) =>
                      const SizedBox(width: 48, height: 48),
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
                  Text(
                    t.fromStreamAddon
                        ? '${t.sourceName} · stream'
                        : t.sourceName,
                  ).xSmall().muted(),
                ],
              ),
            ),
            if (playing)
              Icon(LucideIcons.volume2, size: 16),
          ],
        ),
      ),
    );
  }
}
