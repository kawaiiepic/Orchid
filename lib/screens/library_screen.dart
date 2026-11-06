import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/foundation.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/music_library.dart';
import '../services/orchid_account.dart';
import '../services/player_service.dart';
import '../widgets/mini_player_bar.dart';
import 'song_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  final MusicLibrary library;
  final OrchidAccount account;
  final PlayerService player;
  final AddonService addonService;
  final List<InstalledAddon> addons;
  final VoidCallback openExplore;
  const LibraryScreen({
    super.key,
    required this.library,
    required this.account,
    required this.player,
    required this.addonService,
    required this.addons,
    required this.openExplore,
  });
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _name = TextEditingController();
  List<SavedSong> _lastfm = [];
  List<List<SavedSong>> _serverMixes = [];
  bool _loadingMixes = false;
  String? _mixError;

  @override
  void initState() {
    super.initState();
    _loadMixes();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadMixes() async {
    if (!widget.account.lastfmConnected) return;
    setState(() { _loadingMixes = true; _mixError = null; });
    try {
      final data = await widget.account.lastfmHome();
      final raw = data['recent'];
      if (!mounted) return;
      final result = <SavedSong>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final title = (item['title'] ?? '').toString();
          final artist = (item['artist'] ?? '').toString();
          if (title.isEmpty || artist.isEmpty) continue;
          result.add(SavedSong(title, artist,
            album: item['album']?.toString(), artwork: item['image']?.toString()));
        }
      }
      setState(() => _lastfm = result);
      // The backend returns recommendations, including new related tracks.
      // Keep local mixes available when its migration has not been deployed.
      try {
        final server = await widget.account.dailyMixes();
        if (!mounted) return;
        final rawMixes = server['mixes'];
        if (rawMixes is List) {
          final parsed = <List<SavedSong>>[];
          for (final mix in rawMixes) {
            if (mix is! Map || mix['tracks'] is! List) {
              parsed.add([]);
              continue;
            }
            parsed.add((mix['tracks'] as List).whereType<Map>().map((song) =>
              SavedSong(
                (song['title'] ?? '').toString(),
                (song['artist'] ?? '').toString(),
                album: song['album']?.toString(),
                artwork: song['image']?.toString(),
              )).where((song) => song.title.isNotEmpty &&
                  song.artist.isNotEmpty).toList());
          }
          setState(() => _serverMixes = parsed);
        }
      } catch (e) {
        debugPrint('[Orchid] Using local mixes until backend is available: $e');
      }
    } catch (e) {
      if (mounted) setState(() => _mixError = 'Last.fm mixes unavailable: $e');
    } finally {
      if (mounted) setState(() => _loadingMixes = false);
    }
  }

  void _openSong(SavedSong song) {
    Navigator.of(context).push(ShadcnPageRoute<void>(
      builder: (_) => SongDetailScreen(
        player: widget.player,
        addonService: widget.addonService,
        addons: widget.addons,
        title: song.title,
        artist: song.artist,
        album: song.album,
        artworkUrl: song.artwork,
        library: widget.library,
      ),
    ));
  }

  Future<void> _playCollection(List<SavedSong> songs) async {
    if (songs.isEmpty) return;
    widget.player.setAddons(widget.addons);
    // Source-independent tracks: PlayerService looks for a matching stream
    // through whichever addons are currently installed.
    final queue = songs.map((song) => TrackResult(
      id: song.key,
      title: song.title,
      artist: song.artist,
      album: song.album,
      artworkUrl: song.artwork,
      sourceId: 'orchid-library',
      sourceName: 'Library',
    )).toList();
    try {
      await widget.player.playTrack(queue.first, fromQueue: queue);
    } catch (e) {
      debugPrint('[Orchid Library] Playlist playback failed: $e');
    }
  }

  void _openCollection(String title, List<SavedSong> Function() items,
      {MusicPlaylist? playlist}) {
    Navigator.of(context).push(ShadcnPageRoute<void>(
      builder: (_) => Scaffold(
        footers: [MiniPlayerBar(player: widget.player)],
        child: ListenableBuilder(
          listenable: widget.library,
          builder: (context, _) {
            final songs = items();
            return ListView(padding: const EdgeInsets.all(20), children: [
              Align(alignment: Alignment.centerLeft, child: IconButton.ghost(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => Navigator.of(context).pop(),
              )),
              const SizedBox(height: 16),
              Text(title).x2Large().semiBold(),
              const SizedBox(height: 8),
              Text('${songs.length} tracks').muted(),
              const SizedBox(height: 14),
              if (songs.isNotEmpty)
                PrimaryButton(
                  onPressed: () => _playCollection(songs),
                  child: const Text('Play all'),
                ),
              const SizedBox(height: 10),
              if (playlist != null)
                OutlineButton(
                  onPressed: () async {
                    await widget.library.deletePlaylist(playlist);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Delete playlist'),
                ),
              const SizedBox(height: 14),
              if (songs.isEmpty)
                const Text('No songs yet. Explore music and add your favorites.').muted()
              else
                ...songs.map((song) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Button(
                      style: const ButtonStyle.ghost(),
                      onPressed: () => _openSong(song),
                      child: Row(children: [
                        const Icon(LucideIcons.music2, size: 18),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(song.title).semiBold(),
                            Text(song.artist).small().muted(),
                          ],
                        )),
                      ]),
                    )),
                    if (playlist != null) IconButton.ghost(
                      onPressed: () => widget.library.removeFromPlaylist(playlist, song),
                      icon: const Icon(LucideIcons.x, size: 18),
                    ),
                  ]),
                )),
            ]);
          },
        ),
      ),
    ));
  }

  Widget _collectionTile(String title, String subtitle, VoidCallback open,
      {IconData icon = LucideIcons.listMusic}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Button(
        style: const ButtonStyle.ghost(),
        onPressed: open,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Icon(icon, size: 24),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(title).semiBold(), Text(subtitle).small().muted()],
            )),
            const Icon(LucideIcons.chevronRight, size: 18),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Your Library').x2Large().semiBold(),
        const SizedBox(height: 14),
        _collectionTile('Favorites', '${widget.library.favorites.length} songs',
          () => _openCollection('Favorites', () => widget.library.favorites),
          icon: LucideIcons.heart),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: const Text('Your Playlists').large().semiBold()),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            controller: _name,
            placeholder: const Text('New playlist name'),
            onSubmitted: (_) => _createPlaylist(),
          )),
          const SizedBox(width: 8),
          PrimaryButton(
            onPressed: _createPlaylist,
            child: const Text('Create'),
          ),
        ]),
        const SizedBox(height: 10),
        if (widget.library.playlists.isEmpty)
          const Text('Create a playlist, then add tracks from any song page.').muted()
        else
          ...widget.library.playlists.map((p) => _collectionTile(
            p.name, '${p.songs.length} songs',
            () => _openCollection(p.name, () => p.songs, playlist: p),
          )),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: const Text('Daily Mixes').large().semiBold()),
          IconButton.ghost(
            onPressed: _loadingMixes ? null : _loadMixes,
            icon: const Icon(LucideIcons.refreshCw),
          ),
        ]),
        const SizedBox(height: 4),
        const Text('Refreshed daily from your favorites and recent listening.').small().muted(),
        if (_mixError != null)
          Text(_mixError!).small().muted(),
        const SizedBox(height: 8),
        for (var i = 0; i < 3; i++)
          Builder(builder: (context) {
            final mixIndex = i;
            final songs = _mixSongs(mixIndex);
            final titles = ['Favorites Mix', 'Similar Sounds', 'Discover'];
            return _collectionTile(
              titles[i],
              _loadingMixes ? 'Updating…' : '${songs.length} songs · changes daily',
              () => _openCollection(titles[mixIndex],
                () => _mixSongs(mixIndex)),
              icon: LucideIcons.sparkles,
            );
          }),
        if (widget.library.favorites.isEmpty &&
            widget.library.recentlyPlayed.isEmpty && _lastfm.isEmpty) ...[
          const SizedBox(height: 8),
          const Text('Play or favorite some tracks to build your mixes. Connect Last.fm for more listening history.').muted(),
          const SizedBox(height: 12),
          OutlineButton(onPressed: widget.openExplore, child: const Text('Explore songs')),
        ],
      ],
    ),
  );

  List<SavedSong> _mixSongs(int index) {
    if (index < _serverMixes.length && _serverMixes[index].isNotEmpty) {
      return _serverMixes[index];
    }
    return widget.library.dailyMix(index, _lastfm);
  }

  Future<void> _createPlaylist() async {
    final value = _name.text.trim();
    if (value.isEmpty) return;
    await widget.library.createPlaylist(value);
    if (mounted) _name.clear();
  }
}
