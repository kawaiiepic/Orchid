import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../widgets/orchid_adaptive_controls.dart';

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
  final String? selectedPlaylistId;
  final ValueChanged<String?>? onPlaylistSelected;
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
    this.selectedPlaylistId,
    this.onPlaylistSelected,
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
                OrchidAdaptiveControls.button(prominent: true, 
                  onPressed: () => _playCollection(songs),
                  child: const Text('Play all'),
                ),
              const SizedBox(height: 10),
              if (playlist != null) ...[
                OrchidAdaptiveControls.button(
                  onPressed: () => widget.library.setPlaylistPinned(
                    playlist, !playlist.pinned),
                  child: Text(playlist.pinned
                    ? 'Unpin from Home' : 'Pin to Home'),
                ),
                const SizedBox(height: 8),
                OrchidAdaptiveControls.button(
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

  TrackResult _track(SavedSong song) => TrackResult(
    id: song.key, title: song.title, artist: song.artist,
    album: song.album, artworkUrl: song.artwork,
    sourceId: 'orchid-library', sourceName: 'Library',
  );

  Widget _songRow(SavedSong song, {MusicPlaylist? playlist}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: SongContextMenu(
      track: _track(song), player: widget.player, library: widget.library,
      child: Row(children: [
        Expanded(child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.player.setAddons(widget.addons);
            widget.player.playTrack(_track(song)).catchError((Object e) {
              debugPrint('[Orchid Library] Playback failed: $e');
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              AppleCover(artist: song.artist, name: song.title,
                album: song.album, fallbackUrl: song.artwork,
                size: 46, radius: 7),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title, maxLines: 1,
                    overflow: TextOverflow.ellipsis).semiBold(),
                  Text(song.artist, maxLines: 1,
                    overflow: TextOverflow.ellipsis).small().muted(),
                ],
              )),
            ]),
          ),
        )),
        IconButton.ghost(
          onPressed: () => _openSong(song),
          icon: const Icon(LucideIcons.info, size: 17),
        ),
        if (playlist != null)
          IconButton.ghost(
            onPressed: () => widget.library.removeFromPlaylist(playlist, song),
            icon: const Icon(LucideIcons.x, size: 17),
          ),
      ]),
    ),
  );

  Widget _playlistButton(String name, List<SavedSong> songs,
      VoidCallback action, {bool favorite = false}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: ColoredBox(
            color: const Color(0x293B244A),
            child: SizedBox(height: 62,
              child: Row(children: [
                if (songs.isNotEmpty)
                  AppleCover(
                    artist: songs.first.artist,
                    name: songs.first.title,
                    fallbackUrl: songs.first.artwork,
                    size: 62, radius: 0,
                  )
                else
                  SizedBox(width: 62, height: 62,
                    child: ColoredBox(color: const Color(0x444B2F62),
                      child: Icon(favorite ? LucideIcons.heart
                        : LucideIcons.listMusic, color: OrchidStyle.lilac))),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1,
                      overflow: TextOverflow.ellipsis).semiBold(),
                    Text('${songs.length} songs').small().muted(),
                  ],
                )),
                const Icon(LucideIcons.chevronRight,
                  color: OrchidStyle.lilac, size: 17),
                const SizedBox(width: 12),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final playlists = widget.library.visiblePlaylists;
      final id = widget.selectedPlaylistId;
      MusicPlaylist? activePlaylist;
      if (id != null && id != 'favorites') {
        for (final playlist in playlists) {
          if (playlist.id == id) {
            activePlaylist = playlist;
            break;
          }
        }
      }
      final selected = id == 'favorites' || activePlaylist != null;
      final selectedSongs = id == 'favorites'
        ? widget.library.favorites
        : activePlaylist?.songs ?? <SavedSong>[];
      final selectedTitle = id == 'favorites'
        ? 'Favorites' : activePlaylist?.name ?? 'Playlists';
      return ListView(
        padding: EdgeInsets.fromLTRB(24, 24, 30,
          28 + OrchidStyle.iosDockClearance(context) +
          (MediaQuery.sizeOf(context).width >= 850 ? 104 : 0)),
        children: [
          widget.header,
          if (!widget.playlistsOnly) ...[
            const Text('Library').x2Large().semiBold(),
            const SizedBox(height: 8),
            Text('${widget.library.librarySongs.length} saved songs').small().muted(),
            const SizedBox(height: 20),
            if (widget.library.librarySongs.isEmpty)
              const Text('Your saved songs will appear here.').muted()
            else
              ...widget.library.librarySongs.map(_songRow),
          ] else if (selected) ...[
            if (widget.onPlaylistSelected != null)
              Align(alignment: Alignment.centerLeft,
                child: IconButton.ghost(
                  onPressed: () => widget.onPlaylistSelected!(null),
                  icon: const Icon(LucideIcons.arrowLeft))),
            Text(selectedTitle).x2Large().semiBold(),
            const SizedBox(height: 6),
            Text('${selectedSongs.length} songs').small().muted(),
            const SizedBox(height: 16),
            if (selectedSongs.isNotEmpty)
              Align(alignment: Alignment.centerLeft,
                child: OrchidAdaptiveControls.button(
                  prominent: true,
                  onPressed: () => _playCollection(selectedSongs),
                  child: const Text('Play all'),
                )),
            if (activePlaylist != null) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                OrchidAdaptiveControls.button(
                  onPressed: () => widget.library.setPlaylistPinned(
                    activePlaylist!, !activePlaylist!.pinned),
                  child: Text(activePlaylist.pinned
                    ? 'Unpin from Home' : 'Pin to Home'),
                ),
                OrchidAdaptiveControls.button(
                  onPressed: () async {
                    await widget.library.deletePlaylist(activePlaylist!);
                    widget.onPlaylistSelected?.call(null);
                  },
                  child: const Text('Delete playlist'),
                ),
              ]),
            ],
            const SizedBox(height: 18),
            if (selectedSongs.isEmpty)
              const Text('This playlist is empty.').muted()
            else
              ...selectedSongs.map((song) =>
                _songRow(song, playlist: activePlaylist)),
          ] else ...[
            const Text('Playlists').x2Large().semiBold(),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, bounds) {
              final desktop = bounds.maxWidth >= 600;
              const gap = 12.0;
              final width = desktop
                ? (bounds.maxWidth - gap) / 2
                : bounds.maxWidth;
              return Wrap(
                spacing: gap, runSpacing: gap,
                children: [
                  SizedBox(width: width,
                    child: _playlistButton('Favorites',
                      widget.library.favorites,
                      () => widget.onPlaylistSelected?.call('favorites'),
                      favorite: true)),
                  for (final playlist in playlists)
                    SizedBox(width: width,
                      child: _playlistButton(
                        playlist.name, playlist.songs,
                        () => widget.onPlaylistSelected?.call(playlist.id))),
                ],
              );
            }),
          ],
        ],
      );
    },
  );
}
