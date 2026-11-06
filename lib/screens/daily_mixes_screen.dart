import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/music_library.dart';
import '../services/orchid_account.dart';
import '../services/player_service.dart';
import '../widgets/mini_player_bar.dart';
import '../widgets/apple_cover.dart';
import 'song_detail_screen.dart';
import '../widgets/song_context_menu.dart';

class DailyMixesScreen extends StatefulWidget {
  final int? initialMixIndex;
  final OrchidAccount account;
  final MusicLibrary library;
  final PlayerService player;
  final AddonService addonService;
  final List<InstalledAddon> addons;

  const DailyMixesScreen({
    super.key, this.initialMixIndex, required this.account, required this.library,
    required this.player, required this.addonService, required this.addons,
  });

  @override
  State<DailyMixesScreen> createState() => _DailyMixesScreenState();
}

class _DailyMixesScreenState extends State<DailyMixesScreen> {
  List<List<SavedSong>> _serverMixes = [];
  List<SavedSong> _recentHistory = [];
  int? _selectedMix;
  bool _loading = false;
  String? _error;
  String? _mixError;
  final Map<String, String> _appleArtwork = {};
  int _artworkGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selectedMix = widget.initialMixIndex;
    _refresh();
  }

  List<SavedSong> _mix(int i) =>
      i < _serverMixes.length
          ? _serverMixes[i]
          : i == 2 ? <SavedSong>[] : widget.library.dailyMix(i, _recentHistory);

  Future<void> _loadAppleArtwork(List<List<SavedSong>> mixes) async {
    final generation = ++_artworkGeneration;
    final unique = <String, SavedSong>{};
    for (final mix in mixes) {
      for (final song in mix) {
        unique.putIfAbsent(song.key, () => song);
      }
    }
    final songs = unique.values.toList();
    // Apple Music's authenticated catalog API is the preferred source.
    // Request a few songs per batch to stay below Worker request limits.
    for (var offset = 0; offset < songs.length; offset += 10) {
      if (!mounted || generation != _artworkGeneration) return;
      final batch = songs.skip(offset).take(10).toList();
      try {
        final artwork = await widget.account.appleArtworkBatch([
          for (final song in batch)
            {
              'artist': song.artist,
              'title': song.title,
              'album': song.album ?? '',
            },
        ]);
        if (!mounted || generation != _artworkGeneration) return;
        setState(() {
          for (var i = 0; i < batch.length; i++) {
            final url = artwork[i];
            if (url != null) _appleArtwork[batch[i].key] = url;
          }
        });
      } catch (error) {
        debugPrint('[Orchid Mix] Apple Music artwork batch failed: $error');
      }
    }
  }

  Future<void> _refresh() async {
    if (!widget.account.signedIn) {
      setState(() => _error = 'Sign in to create your Daily Mixes.');
      return;
    }
    ++_artworkGeneration;
    _appleArtwork.clear();
    setState(() { _loading = true; _error = null; _mixError = null; });
    try {
      // Orchid history lives in Petal D1. Last.fm is not needed for mixes.
      final response = await widget.account.dailyMixes();
      final rawMixes = response['mixes'];
      if (rawMixes is! List) {
        throw StateError('Unexpected Daily Mixes response.');
      }
      if (!mounted) return;
      final mixes = rawMixes.map((raw) {
        if (raw is! Map || raw['tracks'] is! List) return <SavedSong>[];
        return (raw['tracks'] as List).whereType<Map>().map((item) =>
          SavedSong(
            (item['title'] ?? '').toString(),
            (item['artist'] ?? '').toString(),
            album:item['album']?.toString(),
            artwork:item['image']?.toString(),
          ),
        ).where((song) => song.title.isNotEmpty && song.artist.isNotEmpty)
        .toList();
      }).toList();
      setState(() => _serverMixes = mixes);
      _loadAppleArtwork(mixes);
    } catch (error) {
      debugPrint('[Orchid] Database Daily Mixes unavailable: $error');
      if (mounted) {
        setState(() => _mixError = 'Could not generate Daily Mixes: $error');
      }
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

  Widget _mixDetails(int index) {
    final titles = ['Favorites Mix', 'Similar Sounds', 'Discover'];
    return Scaffold(
        footers: [MiniPlayerBar(player: widget.player)],
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Align(alignment: Alignment.centerLeft, child: IconButton.ghost(
            onPressed: () {
              if (widget.initialMixIndex != null) {
                Navigator.of(context).pop();
              } else {
                setState(() => _selectedMix = null);
              }
            },
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
          if (_loading && _mix(index).isEmpty)
            const Text('Preparing your mix…').muted(),
          if (!_loading && _mix(index).isEmpty) ...[
            Text(_mixError ?? (index == 2
                ? 'No unheard Apple Music recommendations are available right now. Try again later.'
                : 'No songs available in this mix yet.')).muted(),
            const SizedBox(height:12),
            OutlineButton(
              onPressed: _refresh,
              child:const Text('Retry'),
            ),
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
                  album: song.album,
                  preferredUrl: _appleArtwork[song.key],
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
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedMix != null) return _mixDetails(_selectedMix!);
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
            if (_error != null || _mixError != null) ...[
              const SizedBox(height: 10),
              Text((_error ?? _mixError)!).small().muted(),
              const SizedBox(height:10),
              OutlineButton(onPressed:_refresh, child:const Text('Retry')),
            ],
            const SizedBox(height: 18),
            for (var i = 0; i < titles.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Button(
                  style: const ButtonStyle.ghost(),
                  onPressed: () => setState(() => _selectedMix = i),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      if (_mix(i).isNotEmpty)
                        AppleCover(
                          artist: _mix(i).first.artist,
                          name: _mix(i).first.title,
                          fallbackUrl: _mix(i).first.artwork,
                          album: _mix(i).first.album,
                          preferredUrl: _appleArtwork[_mix(i).first.key],
                          size: 48,
                        )
                      else const Icon(LucideIcons.sparkles, size: 24),
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
