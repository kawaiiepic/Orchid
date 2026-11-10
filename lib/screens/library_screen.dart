import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/music_library.dart';
import '../services/orchid_account.dart';
import '../services/player_service.dart';
import '../widgets/mini_player_bar.dart';
import '../widgets/apple_cover.dart';
import 'song_detail_screen.dart';
import '../widgets/orchid_style.dart';
import '../widgets/song_context_menu.dart';

class LibraryScreen extends StatefulWidget {
  final Widget header;
  final MusicLibrary library;
  final OrchidAccount account;
  final PlayerService player;
  final AddonService addonService;
  final List<InstalledAddon> addons;
  final VoidCallback openExplore;
  final bool playlistsOnly;
  const LibraryScreen({
    super.key,
    required this.header,
    required this.library,
    required this.account,
    required this.player,
    required this.addonService,
    required this.addons,
    required this.openExplore,
    this.playlistsOnly = false,
  });
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  void _openSong(SavedSong song) {
    showSongDetailDrawer(context,
      player:widget.player, addonService:widget.addonService,
      addons:widget.addons, library:widget.library,
      title:song.title, artist:song.artist,
      album:song.album, artworkUrl:song.artwork,
    );
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
        footers: [MiniPlayerBar(player: widget.player, library: widget.library)],
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
                        AppleCover(
                          artist:song.artist,
                          name:song.title,
                          album:song.album,
                          fallbackUrl:song.artwork,
                          size:44,
                          radius:8,
                        ),
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
        child: OrchidGlassPanel(
          radius: 18,
          child: Padding(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) => ListView(
      padding: EdgeInsets.fromLTRB(20,20,20,
        20+OrchidStyle.iosDockClearance(context)+
        (MediaQuery.sizeOf(context).width >= 850 ? 110 : 0)),
      children: [
        widget.header,
        if (widget.playlistsOnly) ...[
          const OrchidHero(
            eyebrow: 'Your collection',
            title: 'Playlists',
            description: 'Your handpicked collections, saved and synced.',
            icon: LucideIcons.listMusic,
          ),
          const SizedBox(height: 26),
          _collectionTile(
            'Favorites', '${widget.library.favorites.length} songs',
            () => _openCollection('Favorites', () => widget.library.favorites),
            icon: LucideIcons.heart,
          ),
          const SizedBox(height: 18),
          const OrchidSectionHeader(title: 'Your playlists'),
          const SizedBox(height: 8),
          if (widget.library.visiblePlaylists.isEmpty)
            const Text('Right-click a song and choose Create new playlist to get started.').muted()
          else
            ...widget.library.visiblePlaylists.map((p) => _collectionTile(
              p.name, '${p.songs.length} songs',
              () => _openCollection(p.name, () => p.songs, playlist: p),
            )),
        ] else ...[
          const OrchidHero(
            eyebrow: 'Your collection',
            title: 'Your Library',
            description: 'Every song you saved, favorited or added to a playlist.',
            icon: LucideIcons.library,
          ),
          const SizedBox(height: 22),
          _collectionTile(
            'Saved songs', '${widget.library.librarySongs.length} songs',
            () => _openCollection('Your Library',
              () => widget.library.librarySongs),
            icon: LucideIcons.library,
          ),
          const SizedBox(height: 12),
          if (widget.library.librarySongs.isEmpty)
            const Text('Favorite a song or add one to a playlist to build your Library.').muted()
          else ...[
            const OrchidSectionHeader(title: 'Recently added'),
            const SizedBox(height: 10),
            ...widget.library.librarySongs.take(30).map(
              (song) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SongContextMenu(
                  track: TrackResult(
                    id: song.key, title: song.title, artist: song.artist,
                    album: song.album, artworkUrl: song.artwork,
                    sourceId: 'orchid-library', sourceName: 'Library',
                  ),
                  player: widget.player, library: widget.library,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openSong(song),
                    child: Row(children: [
                      AppleCover(artist: song.artist, name: song.title,
                        album: song.album, fallbackUrl: song.artwork,
                        size: 44, radius: 8),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(song.title).semiBold(),
                          Text(song.artist).small().muted(),
                        ],
                      )),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    ),
  );
}
