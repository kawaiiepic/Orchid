import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/foundation.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/music_library.dart';
import '../services/orchid_account.dart';
import '../services/player_service.dart';
import '../widgets/mini_player_bar.dart';
import 'song_detail_screen.dart';
import '../widgets/orchid_style.dart';
import '../widgets/song_context_menu.dart';

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
              if (playlist != null) ...[
                OutlineButton(
                  onPressed: () => widget.library.setPlaylistPinned(
                    playlist, !playlist.pinned),
                  child: Text(playlist.pinned
                    ? 'Unpin from Home' : 'Pin to Home'),
                ),
                const SizedBox(height: 8),
                OutlineButton(
                  onPressed: () async {
                    await widget.library.deletePlaylist(playlist);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Delete playlist'),
                ),
              ],
              const SizedBox(height: 14),
              if (songs.isEmpty)
                const Text('No songs yet. Explore music and add your favorites.').muted()
              else
                ...songs.map((song) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: SongContextMenu(
                    track: TrackResult(
                      id: song.key,
                      title: song.title,
                      artist: song.artist,
                      album: song.album,
                      artworkUrl: song.artwork,
                      sourceId: 'orchid-library',
                      sourceName: 'Library',
                    ),
                    player: widget.player,
                    library: widget.library,
                    child: Row(children: [
                    Expanded(child: Button(
                      style: const ButtonStyle.ghost(),
                      onPressed: () {
                        widget.player.setAddons(widget.addons);
                        widget.player.playTrack(TrackResult(
                          id: song.key,
                          title: song.title,
                          artist: song.artist,
                          album: song.album,
                          artworkUrl: song.artwork,
                          sourceId: 'orchid-library',
                          sourceName: 'Library',
                        )).catchError((Object e) {
                          debugPrint('[Orchid Library] Track playback failed: $e');
                        });
                      },
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
                    IconButton.ghost(
                      onPressed: () => _openSong(song),
                      icon: const Icon(LucideIcons.info, size: 18),
                    ),
                    if (playlist != null) IconButton.ghost(
                      onPressed: () => widget.library.removeFromPlaylist(playlist, song),
                      icon: const Icon(LucideIcons.x, size: 18),
                    ),
                  ]),
                  ),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: open,
        child: Container(
          decoration: OrchidStyle.panelDecoration(radius: 18),
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF644184), Color(0xFF342544)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: OrchidStyle.lilac, size: 23),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title).semiBold(),
                const SizedBox(height: 4),
                Text(subtitle).small().muted(),
              ],
            )),
            const Icon(LucideIcons.chevronRight,
              color: OrchidStyle.lilac, size: 18),
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
        const OrchidHero(
          eyebrow: 'Your collection',
          title: 'Keep what you love.',
          description: 'All your favorites and handpicked playlists, together in one place.',
          icon: LucideIcons.library,
        ),
        const SizedBox(height: 26),
        const OrchidSectionHeader(title: 'Liked songs'),

        _collectionTile('Favorites', '${widget.library.favorites.length} songs',
          () => _openCollection('Favorites', () => widget.library.favorites),
          icon: LucideIcons.heart),
        const SizedBox(height: 24),
        const OrchidSectionHeader(
          title: 'Your playlists',
          subtitle: 'Little worlds built one song at a time',
        ),
        const SizedBox(height: 8),
        if (widget.library.playlists.isEmpty)
          const Text('Right-click a song and choose Create new playlist to get started.').muted()
        else
          ...widget.library.playlists.map((p) => _collectionTile(
            p.name, '${p.songs.length} songs',
            () => _openCollection(p.name, () => p.songs, playlist: p),
          )),
      ],
    ),
  );

}
