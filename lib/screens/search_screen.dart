import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/player_service.dart';
import '../services/music_library.dart';
import 'song_detail_screen.dart';
import '../widgets/orchid_style.dart';

class SearchScreen extends StatefulWidget {
  final AddonService addonService;
  final PlayerService player;
  final MusicLibrary library;
  final List<InstalledAddon> addons;

  const SearchScreen({
    super.key,
    required this.addonService,
    required this.player,
    required this.library,
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

  void _openSong(TrackResult track) {
    Navigator.of(context).push(
      ShadcnPageRoute<void>(
        builder:(_)=>SongDetailScreen(
          player:widget.player,
          addonService:widget.addonService,
          addons:widget.addons,
          title:track.title,
          artist:track.artist,
          album:track.album,
          artworkUrl:track.artworkUrl,
          track:track,
          library:widget.library,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: OrchidHero(
            eyebrow: 'Explore',
            title: 'Find your next favorite.',
            description: 'Artists, albums and songs are only a search away.',
            icon: LucideIcons.search,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  placeholder: const Text('Search a song or artist…'),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: GestureDetector(
        onTap: () => _openSong(t),
        child: Container(
          decoration: OrchidStyle.panelDecoration(radius: 15),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
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
              const Icon(LucideIcons.volume2, size: 16),
          ],
        ),
        ),
      ),
    );
  }
}
