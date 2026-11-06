import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/music_library.dart';
import '../services/orchid_account.dart';
import '../services/apple_catalog_service.dart';
import '../services/player_service.dart';
import '../widgets/mini_player_bar.dart';
import '../widgets/apple_cover.dart';
import 'song_detail_screen.dart';
import '../widgets/song_context_menu.dart';

class DailyMixesScreen extends StatefulWidget {
  final OrchidAccount account;
  final MusicLibrary library;
  final PlayerService player;
  final AddonService addonService;
  final List<InstalledAddon> addons;

  const DailyMixesScreen({
    super.key, required this.account, required this.library,
    required this.player, required this.addonService, required this.addons,
  });

  @override
  State<DailyMixesScreen> createState() => _DailyMixesScreenState();
}

class _DailyMixesScreenState extends State<DailyMixesScreen> {
  List<List<SavedSong>> _serverMixes = [];
  List<SavedSong> _lastfmSongs = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  List<SavedSong> _mix(int i) =>
      i < _serverMixes.length && _serverMixes[i].isNotEmpty
          ? _serverMixes[i]
          : widget.library.dailyMix(i, _lastfmSongs);

  Future<void> _refresh() async {
    if (!widget.account.lastfmConnected) {
      setState(() {
        _error = 'Connect Last.fm to improve your Daily Mixes.';
      });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final home = await widget.account.lastfmHome();
      final recent = home['recent'];
      final tracks = <SavedSong>[];
      if (recent is List) {
        for (final raw in recent) {
          if (raw is! Map) continue;
          final title = (raw['title'] ?? '').toString();
          final artist = (raw['artist'] ?? '').toString();
          if (title.isEmpty || artist.isEmpty) continue;
          final canonical = await AppleCatalogService.instance.matchTrack(
            artist: artist,
            title: title,
            album: raw['album']?.toString(),
          );
          tracks.add(SavedSong(
            canonical?.title ?? title,
            canonical?.artist ?? artist,
            album: canonical?.album ?? raw['album']?.toString(),
            artwork: canonical?.artwork ?? raw['image']?.toString(),
          ));
        }
      }
      if (!mounted) return;
      setState(() => _lastfmSongs = tracks);

      try {
        final response = await widget.account.dailyMixes();
        final rawMixes = response['mixes'];
        if (rawMixes is List && mounted) {
          setState(() => _serverMixes = rawMixes.map((raw) {
            if (raw is! Map || raw['tracks'] is! List) return <SavedSong>[];
            return (raw['tracks'] as List).whereType<Map>().map((item) =>
                SavedSong((item['title'] ?? '').toString(),
                  (item['artist'] ?? '').toString(),
                  album: item['album']?.toString(),
                  artwork: item['image']?.toString(),
                )).where((s) => s.title.isNotEmpty && s.artist.isNotEmpty)
                .toList();
          }).toList());
        }
      } catch (e) {
        debugPrint('[Orchid] Backend Daily Mixes unavailable: $e');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not refresh Last.fm history: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playMix(int index) async {
    final songs = _mix(index);
    if (songs.isEmpty) return;
    widget.player.setAddons(widget.addons);
    final queue = songs.map((song) => TrackResult(
      id: song.key, title: song.title, artist: song.artist,
      album: song.album, artworkUrl: song.artwork,
      sourceId: 'orchid-mix', sourceName: 'Daily Mix',
    )).toList();
    try {
      await widget.player.playTrack(queue.first, fromQueue: queue);
    } catch (e) {
      debugPrint('[Orchid] Daily Mix playback failed: $e');
    }
  }

  void _openMix(int index) {
    final titles = ['Favorites Mix', 'Similar Sounds', 'Discover'];
    Navigator.of(context).push(ShadcnPageRoute<void>(
      builder: (_) => Scaffold(
        footers: [MiniPlayerBar(player: widget.player)],
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Align(alignment: Alignment.centerLeft, child: IconButton.ghost(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(LucideIcons.arrowLeft),
          )),
          const SizedBox(height: 16),
          Text(titles[index]).x2Large().semiBold(),
          const SizedBox(height: 12),
          if (_mix(index).isNotEmpty) ...[
            PrimaryButton(
              onPressed: () => _playMix(index),
              child: const Text('Play all'),
            ),
            const SizedBox(height: 12),
          ],
          ..._mix(index).map((song) => SongContextMenu(
            track: TrackResult(
              id: song.key, title: song.title, artist: song.artist,
              album: song.album, artworkUrl: song.artwork,
              sourceId: 'orchid-mix', sourceName: 'Daily Mix',
            ),
            player: widget.player, library: widget.library,
            child: Button(
            style: const ButtonStyle.ghost(),
            onPressed: () {
              widget.player.setAddons(widget.addons);
              widget.player.playTrack(TrackResult(
                id:song.key,title:song.title,artist:song.artist,
                album:song.album,artworkUrl:song.artwork,
                sourceId:'orchid-mix',sourceName:'Daily Mix',
              )).catchError((Object e) {
                debugPrint('[Orchid Mix] Playback failed: $e');
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                AppleCover(
                  artist: song.artist,
                  name: song.title,
                  fallbackUrl: song.artwork,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title).semiBold(),
                    Text(song.artist).small().muted(),
                  ],
                )),
                IconButton.ghost(
                  onPressed:()=>showSongDetailDrawer(context,
                    player:widget.player,
                    addonService:widget.addonService,
                    addons:widget.addons,
                    library:widget.library,
                    title:song.title, artist:song.artist,
                    album:song.album, artworkUrl:song.artwork,
                  ),
                  icon:const Icon(LucideIcons.info,size:18),
                ),
              ]),
            ),
            ),
          )),
        ]),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Favorites Mix', 'Similar Sounds', 'Discover'];
    return Scaffold(
      footers: [MiniPlayerBar(player: widget.player)],
      child: ListenableBuilder(
        listenable: widget.library,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Align(alignment: Alignment.centerLeft, child: IconButton.ghost(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(LucideIcons.arrowLeft),
            )),
            const SizedBox(height: 16),
            const Text('Daily Mixes').x2Large().semiBold(),
            const SizedBox(height: 8),
            const Text('A new rotation every day, based on your listening.').muted(),
            const SizedBox(height: 16),
            if (_loading)
              const Text('Preparing your mixes…').small().muted(),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!).small().muted(),
            ],
            const SizedBox(height: 18),
            for (var i = 0; i < titles.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Button(
                  style: const ButtonStyle.ghost(),
                  onPressed: () => _openMix(i),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      const Icon(LucideIcons.sparkles, size: 24),
                      const SizedBox(width: 16),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(titles[i]).semiBold(),
                          Text('${_mix(i).length} songs').small().muted(),
                        ],
                      )),
                      const Icon(LucideIcons.chevronRight, size: 18),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
